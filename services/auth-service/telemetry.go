package main

// Instrumentação OpenTelemetry (Fase 4).
//
// Traces e métricas são enviados por OTLP/gRPC ao gateway do OpenTelemetry
// Collector (variável OTEL_EXPORTER_OTLP_ENDPOINT). Os logs continuam na
// saída padrão — de onde o agente do Collector os coleta — e recebem
// trace_id/span_id para correlação com os traces.

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

const instrumentationName = "togglemaster"

// Limites (em segundos) dos histogramas de duração.
var durationBuckets = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10}

// Telemetry reúne o tracer e os instrumentos de métrica do serviço.
type Telemetry struct {
	Tracer       trace.Tracer
	httpRequests metric.Int64Counter
	httpDuration metric.Float64Histogram
	shutdown     func(context.Context) error
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// initTelemetry configura os provedores globais de traces e métricas.
// Sem OTEL_EXPORTER_OTLP_ENDPOINT (ou com OTEL_SDK_DISABLED=true) a telemetria
// fica inativa (no-op): o serviço funciona normalmente em testes e dev local.
func initTelemetry(ctx context.Context, serviceName string) (*Telemetry, error) {
	t := &Telemetry{shutdown: func(context.Context) error { return nil }}

	enabled := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") != "" && os.Getenv("OTEL_SDK_DISABLED") != "true"
	if enabled {
		res, err := resource.New(ctx,
			resource.WithAttributes(
				attribute.String("service.name", serviceName),
				attribute.String("service.namespace", "togglemaster"),
				attribute.String("service.version", envOr("SERVICE_VERSION", "dev")),
				attribute.String("deployment.environment.name", envOr("DEPLOYMENT_ENVIRONMENT", "lab")),
			),
			resource.WithFromEnv(), // OTEL_RESOURCE_ATTRIBUTES / OTEL_SERVICE_NAME têm precedência
			resource.WithTelemetrySDK(),
		)
		if err != nil && res == nil {
			return t, fmt.Errorf("resource: %w", err)
		}

		traceExp, err := otlptracegrpc.New(ctx)
		if err != nil {
			return t, fmt.Errorf("exportador de traces: %w", err)
		}
		tp := sdktrace.NewTracerProvider(
			sdktrace.WithBatcher(traceExp),
			sdktrace.WithResource(res),
		)
		otel.SetTracerProvider(tp)

		metricExp, err := otlpmetricgrpc.New(ctx)
		if err != nil {
			return t, fmt.Errorf("exportador de métricas: %w", err)
		}
		mp := sdkmetric.NewMeterProvider(
			sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp, sdkmetric.WithInterval(15*time.Second))),
			sdkmetric.WithResource(res),
		)
		otel.SetMeterProvider(mp)

		t.shutdown = func(c context.Context) error {
			return errors.Join(tp.Shutdown(c), mp.Shutdown(c))
		}
		log.Printf("OpenTelemetry habilitado (endpoint OTLP: %s)", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))
	} else {
		log.Println("OpenTelemetry inativo (OTEL_EXPORTER_OTLP_ENDPOINT não definido)")
	}

	// Propagação W3C Trace Context (traceparent/tracestate) + Baggage.
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	t.Tracer = otel.Tracer(instrumentationName)
	meter := otel.Meter(instrumentationName)

	var err error
	if t.httpRequests, err = meter.Int64Counter("togglemaster.http.server.requests",
		metric.WithDescription("Requisições HTTP recebidas (health checks excluídos)"),
		metric.WithUnit("{request}")); err != nil {
		return t, err
	}
	if t.httpDuration, err = meter.Float64Histogram("togglemaster.http.server.duration",
		metric.WithDescription("Duração das requisições HTTP recebidas"),
		metric.WithUnit("s"),
		metric.WithExplicitBucketBoundaries(durationBuckets...)); err != nil {
		return t, err
	}
	return t, nil
}

// outcomeFor classifica o resultado da requisição a partir do código HTTP.
func outcomeFor(status int) string {
	switch {
	case status >= 500:
		return "server_error"
	case status >= 400:
		return "client_error"
	default:
		return "success"
	}
}

// statusRecorder captura o código de resposta escrito pelo handler.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// normalizeRoute devolve a rota registrada (baixa cardinalidade) ou "unmatched".
func normalizeRoute(path string, routes []string) string {
	for _, r := range routes {
		if path == r {
			return r
		}
	}
	return "unmatched"
}

// instrumentHTTP adiciona spans de servidor (otelhttp) e as métricas de
// aplicação. O endpoint /health não gera spans nem métricas de negócio.
func (t *Telemetry) instrumentHTTP(next http.Handler, routes []string) http.Handler {
	measured := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		attrs := metric.WithAttributes(
			attribute.String("http.request.method", r.Method),
			attribute.String("http.route", normalizeRoute(r.URL.Path, routes)),
			attribute.String("http.response.status_code", strconv.Itoa(rec.status)),
			attribute.String("outcome", outcomeFor(rec.status)),
		)
		t.httpRequests.Add(r.Context(), 1, attrs)
		t.httpDuration.Record(r.Context(), time.Since(start).Seconds(), attrs)
	})

	return otelhttp.NewHandler(measured, "http.server",
		otelhttp.WithFilter(func(r *http.Request) bool { return r.URL.Path != "/health" }),
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string {
			return r.Method + " " + normalizeRoute(r.URL.Path, routes)
		}),
	)
}

// logCtx registra a mensagem com trace_id e span_id quando há span ativo,
// permitindo relacionar o log (Loki) ao trace (APM).
func logCtx(ctx context.Context, format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		log.Printf("%s trace_id=%s span_id=%s", msg, sc.TraceID().String(), sc.SpanID().String())
		return
	}
	log.Print(msg)
}
