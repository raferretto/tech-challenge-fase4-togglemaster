"""Instrumentação OpenTelemetry dos serviços Python do ToggleMaster (Fase 4).

Traces e métricas são enviados por OTLP/gRPC ao gateway do OpenTelemetry
Collector (variável OTEL_EXPORTER_OTLP_ENDPOINT). Os logs continuam na saída
padrão, de onde o agente do Collector os coleta, e recebem trace_id/span_id
para correlação com os traces.

Sem OTEL_EXPORTER_OTLP_ENDPOINT (ou com OTEL_SDK_DISABLED=true) a telemetria
fica inativa (no-op) e o serviço funciona normalmente em testes e dev local.

Este arquivo é idêntico nos serviços flag, targeting e analytics: cada serviço
tem o seu próprio contexto de build Docker.
"""
import logging
import os
import time
from contextlib import contextmanager

from opentelemetry import metrics, propagate, trace
from opentelemetry.trace import SpanKind, Status, StatusCode

INSTRUMENTATION_NAME = "togglemaster"

# Limites (em segundos) dos histogramas de duração.
DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

_state = {"enabled": False, "service": "unknown"}


def _telemetry_enabled():
    return bool(os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")) and os.getenv("OTEL_SDK_DISABLED", "").lower() != "true"


class TraceContextFilter(logging.Filter):
    """Acrescenta trace_id e span_id a cada registro de log (ou '-' sem span ativo)."""

    def filter(self, record):
        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            record.trace_id = format(ctx.trace_id, "032x")
            record.span_id = format(ctx.span_id, "016x")
        else:
            record.trace_id = "-"
            record.span_id = "-"
        return True


def setup_logging():
    """Configura o log na saída padrão com os campos de correlação."""
    handler = logging.StreamHandler()
    handler.addFilter(TraceContextFilter())
    handler.setFormatter(logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s trace_id=%(trace_id)s span_id=%(span_id)s"
    ))
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    # o log de acesso do servidor de desenvolvimento não agrega (há métricas e traces)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)


def init(service_name):
    """Configura os provedores globais de traces e métricas. Chamar antes de criar clientes."""
    _state["service"] = service_name
    setup_logging()
    log = logging.getLogger(__name__)

    if not _telemetry_enabled():
        log.info("OpenTelemetry inativo (OTEL_EXPORTER_OTLP_ENDPOINT não definido)")
        return

    from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.metrics import MeterProvider
    from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    # Resource.create também aplica OTEL_RESOURCE_ATTRIBUTES / OTEL_SERVICE_NAME
    resource = Resource.create({
        "service.name": service_name,
        "service.namespace": "togglemaster",
        "service.version": os.getenv("SERVICE_VERSION", "dev"),
        "deployment.environment.name": os.getenv("DEPLOYMENT_ENVIRONMENT", "lab"),
    })

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)

    reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=15000)
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

    # Chamadas HTTP de saída (ex.: validação da chave no auth-service): cria os
    # spans de cliente e propaga o contexto W3C (traceparent/tracestate).
    try:
        from opentelemetry.instrumentation.requests import RequestsInstrumentor
        RequestsInstrumentor().instrument()
    except ImportError:  # serviço sem chamadas HTTP de saída (analytics)
        pass

    _state["enabled"] = True
    log.info("OpenTelemetry habilitado (endpoint OTLP: %s)", os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))


def tracer():
    return trace.get_tracer(INSTRUMENTATION_NAME)


def meter():
    return metrics.get_meter(INSTRUMENTATION_NAME)


def outcome_for(status):
    if status >= 500:
        return "server_error"
    if status >= 400:
        return "client_error"
    return "success"


def instrument_flask(app):
    """Spans de servidor (FlaskInstrumentor) e métricas de aplicação. /health fica de fora."""
    from flask import g, request

    if _state["enabled"]:
        from opentelemetry.instrumentation.flask import FlaskInstrumentor
        FlaskInstrumentor().instrument_app(app, excluded_urls="health")

    requests_counter = meter().create_counter(
        "togglemaster.http.server.requests", unit="{request}",
        description="Requisições HTTP recebidas (health checks excluídos)")
    duration_histogram = meter().create_histogram(
        "togglemaster.http.server.duration", unit="s",
        description="Duração das requisições HTTP recebidas",
        explicit_bucket_boundaries_advisory=DURATION_BUCKETS)

    @app.before_request
    def _start_timer():
        g._tm_start = time.perf_counter()

    @app.after_request
    def _record_metrics(response):
        if request.path == "/health":
            return response
        # rota normalizada (ex.: /flags/<string:name>) para manter a cardinalidade baixa
        route = request.url_rule.rule if request.url_rule is not None else "unmatched"
        attrs = {
            "http.request.method": request.method,
            "http.route": route,
            "http.response.status_code": str(response.status_code),
            "outcome": outcome_for(response.status_code),
        }
        requests_counter.add(1, attrs)
        start = getattr(g, "_tm_start", None)
        if start is not None:
            duration_histogram.record(time.perf_counter() - start, attrs)
        return response


@contextmanager
def db_span(operation, table):
    """Span de cliente para uma operação no PostgreSQL (sem o conteúdo da consulta)."""
    with tracer().start_as_current_span(
        f"{operation} {table}", kind=SpanKind.CLIENT,
        attributes={"db.system.name": "postgresql", "db.operation.name": operation, "db.collection.name": table},
    ) as span:
        try:
            yield span
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, "falha na operação de banco"))
            raise


class TracedCursor:
    """Envolve um cursor do psycopg2: cada execute() vira um span de cliente."""

    def __init__(self, cursor, table):
        self._cursor = cursor
        self._table = table

    def execute(self, query, params=None):
        operation = query.strip().split(None, 1)[0].upper()
        with db_span(operation, self._table):
            return self._cursor.execute(query, params)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


def traced_cursor(cursor, table):
    return TracedCursor(cursor, table)


def extract_context(carrier):
    """Extrai o contexto de rastreamento de um dicionário (ex.: atributos de mensagem SQS)."""
    return propagate.extract(carrier)
