package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

type EvaluationResponse struct {
	FlagName string `json:"flag_name"`
	UserID   string `json:"user_id"`
	Result   bool   `json:"result"`
}

// faultFile é o arquivo que ativa a falha controlada de laboratório (Fase 4).
// Enquanto ele existir no contêiner, /evaluate responde HTTP 503 e /health
// continua respondendo 200 — reproduzindo a "falha silenciosa" do desafio.
// Só tem efeito com ENABLE_FAULT_INJECTION=true (ambiente de demonstração).
const faultFile = "/tmp/togglemaster-force-503"

func faultInjected() bool {
	if os.Getenv("ENABLE_FAULT_INJECTION") != "true" {
		return false
	}
	_, err := os.Stat(faultFile)
	return err == nil
}

func (a *App) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (a *App) evaluationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	reqCtx := r.Context()
	span := trace.SpanFromContext(reqCtx)

	// 0. Falha controlada (experimento de Self-Healing)
	if faultInjected() {
		span.SetStatus(codes.Error, "fault injection ativo")
		span.SetAttributes(attribute.Bool("togglemaster.fault_injection", true))
		logCtx(reqCtx, "ERRO: falha controlada ativa (%s) - respondendo 503", faultFile)
		http.Error(w, `{"error": "Falha controlada de laboratório (fault injection)"}`, http.StatusServiceUnavailable)
		return
	}

	// 1. Parsear os query parameters
	userID := r.URL.Query().Get("user_id")
	flagName := r.URL.Query().Get("flag_name")

	if userID == "" || flagName == "" {
		http.Error(w, `{"error": "user_id e flag_name são obrigatórios"}`, http.StatusBadRequest)
		return
	}

	// 2. Obter a decisão (lógica de cache/serviço está em evaluator.go)
	result, err := a.getDecision(reqCtx, userID, flagName)
	if err != nil {
		// Se o erro for "não encontrado", retornamos 'false' (comportamento seguro)
		if _, ok := err.(*NotFoundError); ok {
			result = false
		} else {
			// Outros erros (serviços offline, etc)
			span.RecordError(err)
			span.SetStatus(codes.Error, "erro ao avaliar a flag")
			logCtx(reqCtx, "Erro ao avaliar flag '%s': %v", flagName, err)
			http.Error(w, `{"error": "Erro interno ao avaliar a flag"}`, http.StatusBadGateway)
			return
		}
	}

	// 3. Enviar evento para SQS (assincronamente)
	// Isso não bloqueia a resposta para o cliente. O contexto é desvinculado do
	// cancelamento da requisição, mas preserva o trace para o span PRODUCER.
	go a.sendEvaluationEvent(context.WithoutCancel(reqCtx), userID, flagName, result)

	// 4. Retornar a resposta
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(EvaluationResponse{
		FlagName: flagName,
		UserID:   userID,
		Result:   result,
	})
}
