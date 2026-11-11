package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func TestNormalizeRoute(t *testing.T) {
	if got := normalizeRoute("/evaluate", routes); got != "/evaluate" {
		t.Errorf("rota conhecida: esperado /evaluate, obtido %s", got)
	}
	if got := normalizeRoute("/qualquer/coisa/123", routes); got != "unmatched" {
		t.Errorf("rota desconhecida deve ser 'unmatched', obtido %s", got)
	}
}

func TestOutcomeFor(t *testing.T) {
	cases := map[int]string{200: "success", 404: "client_error", 502: "server_error", 503: "server_error"}
	for status, want := range cases {
		if got := outcomeFor(status); got != want {
			t.Errorf("status %d: esperado %s, obtido %s", status, want, got)
		}
	}
}

// O contexto de rastreamento deve ser gravado nos MessageAttributes do SQS.
func TestSqsCarrierInjectsTraceContext(t *testing.T) {
	tel, err := initTelemetry(context.Background(), "evaluation-service-test")
	if err != nil {
		t.Fatalf("initTelemetry: %v", err)
	}
	tp := sdktrace.NewTracerProvider()
	defer tp.Shutdown(context.Background())

	ctx, span := tp.Tracer("test").Start(context.Background(), "parent")
	defer span.End()

	carrier := sqsCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)

	tpHeader := carrier.Get("traceparent")
	if tpHeader == "" {
		t.Fatal("traceparent não foi injetado nos MessageAttributes")
	}
	if dt := carrier["traceparent"].DataType; dt == nil || *dt != "String" {
		t.Error("o atributo traceparent deve ser do tipo String")
	}
	if tel.Tracer == nil {
		t.Error("tracer não inicializado")
	}
}

// Com o arquivo de falha presente (e a injeção habilitada), /evaluate responde
// 503 e /health continua 200; sem a variável de ambiente a falha é ignorada.
func TestFaultInjection(t *testing.T) {
	tel, _ := initTelemetry(context.Background(), "evaluation-service-test")
	app := &App{Tel: tel}

	if err := os.WriteFile(faultFile, []byte("x"), 0o600); err != nil {
		t.Skipf("não foi possível criar %s: %v", faultFile, err)
	}
	defer os.Remove(faultFile)

	t.Setenv("ENABLE_FAULT_INJECTION", "true")
	rec := httptest.NewRecorder()
	app.evaluationHandler(rec, httptest.NewRequest(http.MethodGet, "/evaluate?user_id=u1&flag_name=f1", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("com a falha ativa esperava 503, obtido %d", rec.Code)
	}

	rec = httptest.NewRecorder()
	app.healthHandler(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Errorf("/health deve continuar 200, obtido %d", rec.Code)
	}

	t.Setenv("ENABLE_FAULT_INJECTION", "false")
	if faultInjected() {
		t.Error("a falha não pode ter efeito sem ENABLE_FAULT_INJECTION=true")
	}
}

// A mensagem publicada na fila deve levar o traceparent do span PRODUCER nos
// MessageAttributes (é o que permite ao analytics-service continuar o trace).
func TestSendEvaluationEventPropagatesTraceContext(t *testing.T) {
	var captured string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		captured = string(body)
		w.Header().Set("Content-Type", "application/x-amz-json-1.0")
		_, _ = w.Write([]byte(`{"MessageId":"test","MD5OfMessageBody":"d41d8cd98f00b204e9800998ecf8427e"}`))
	}))
	defer srv.Close()

	tp := sdktrace.NewTracerProvider()
	defer tp.Shutdown(context.Background())
	tel, _ := initTelemetry(context.Background(), "evaluation-service-test")
	tel.Tracer = tp.Tracer("test")

	sess, err := session.NewSession(&aws.Config{
		Region:      aws.String("us-east-1"),
		Endpoint:    aws.String(srv.URL),
		Credentials: credentials.NewStaticCredentials("test", "test", ""),
		MaxRetries:  aws.Int(0),
		// o corpo de teste não traz um MD5 real da mensagem
		DisableComputeChecksums: aws.Bool(true),
	})
	if err != nil {
		t.Fatalf("sessão AWS: %v", err)
	}
	app := &App{SqsSvc: sqs.New(sess), SqsQueueURL: srv.URL + "/queue", Tel: tel}

	ctx, parent := tp.Tracer("test").Start(context.Background(), "GET /evaluate")
	app.sendEvaluationEvent(ctx, "user-1", "checkout_v2", true)
	parent.End()

	traceID := parent.SpanContext().TraceID().String()
	if !strings.Contains(captured, `"traceparent"`) || !strings.Contains(captured, traceID) {
		t.Fatalf("a mensagem SQS não carrega o traceparent do trace %s: %s", traceID, captured)
	}
	if !strings.Contains(captured, `"DataType":"String"`) {
		t.Errorf("o atributo traceparent deve ser do tipo String: %s", captured)
	}
}
