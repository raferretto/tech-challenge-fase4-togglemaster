package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNormalizeRoute(t *testing.T) {
	if got := normalizeRoute("/validate", routes); got != "/validate" {
		t.Errorf("rota conhecida: esperado /validate, obtido %s", got)
	}
	if got := normalizeRoute("/nao-existe", routes); got != "unmatched" {
		t.Errorf("rota desconhecida deve ser 'unmatched', obtido %s", got)
	}
}

// Sem endpoint OTLP a telemetria fica inativa e o middleware não interfere
// nas respostas (incluindo o /health, que não é medido).
func TestInstrumentHTTPPassThrough(t *testing.T) {
	tel, err := initTelemetry(context.Background(), "auth-service-test")
	if err != nil {
		t.Fatalf("initTelemetry: %v", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("/validate", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusUnauthorized) })
	h := tel.instrumentHTTP(mux, routes)

	for path, want := range map[string]int{"/health": 200, "/validate": 401} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != want {
			t.Errorf("%s: esperado %d, obtido %d", path, want, rec.Code)
		}
	}
}
