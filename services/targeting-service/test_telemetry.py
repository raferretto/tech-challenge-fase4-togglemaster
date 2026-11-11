import logging
import os
import unittest

# sem endpoint OTLP a telemetria fica inativa (no-op): os testes não dependem de rede
os.environ.pop("OTEL_EXPORTER_OTLP_ENDPOINT", None)

import telemetry  # noqa: E402


class FakeCursor:
    def __init__(self):
        self.executed = []
        self.rowcount = 1

    def execute(self, query, params=None):
        self.executed.append((query, params))


class TestTelemetry(unittest.TestCase):
    def test_outcome_for(self):
        self.assertEqual(telemetry.outcome_for(200), "success")
        self.assertEqual(telemetry.outcome_for(404), "client_error")
        self.assertEqual(telemetry.outcome_for(503), "server_error")

    def test_init_without_endpoint_is_noop(self):
        telemetry.init("servico-de-teste")
        self.assertFalse(telemetry._state["enabled"])
        # tracer e meter continuam utilizáveis (implementações no-op)
        with telemetry.tracer().start_as_current_span("teste"):
            telemetry.meter().create_counter("teste.contador").add(1)

    def test_traced_cursor_delegates_to_real_cursor(self):
        fake = FakeCursor()
        cursor = telemetry.traced_cursor(fake, "flags")
        cursor.execute("SELECT * FROM flags WHERE name = %s", ("checkout",))
        self.assertEqual(fake.executed, [("SELECT * FROM flags WHERE name = %s", ("checkout",))])
        self.assertEqual(cursor.rowcount, 1)  # atributos não interceptados vêm do cursor real

    def test_log_records_receive_trace_fields(self):
        record = logging.LogRecord("x", logging.INFO, __file__, 1, "mensagem", None, None)
        telemetry.TraceContextFilter().filter(record)
        self.assertEqual(record.trace_id, "-")
        self.assertEqual(record.span_id, "-")

    def test_extract_context_from_sqs_attributes(self):
        from opentelemetry import trace
        carrier = {"traceparent": "00-aaaabbbbccccddddeeeeffff00001111-1234567890abcdef-01"}
        ctx = telemetry.extract_context(carrier)
        span_context = trace.get_current_span(ctx).get_span_context()
        self.assertEqual(format(span_context.trace_id, "032x"), "aaaabbbbccccddddeeeeffff00001111")


if __name__ == "__main__":
    unittest.main()
