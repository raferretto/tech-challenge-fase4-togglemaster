package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// dbSpan abre um span de cliente para uma operação no PostgreSQL.
func (a *App) dbSpan(ctx context.Context, operation string) (context.Context, trace.Span) {
	return a.Tel.Tracer.Start(ctx, operation+" api_keys", trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("db.system.name", "postgresql"),
			attribute.String("db.operation.name", operation),
			attribute.String("db.collection.name", "api_keys"),
		))
}

// Estrutura para o corpo da requisição de criação de chave
type CreateKeyRequest struct {
	Name string `json:"name"`
}

// Estrutura para a resposta da criação de chave
type CreateKeyResponse struct {
	Name    string `json:"name"`
	Key     string `json:"key"` // A chave em texto plano é retornada APENAS uma vez
	Message string `json:"message"`
}

// healthHandler é um simples endpoint de verificação de saúde
func (a *App) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// validateKeyHandler verifica se uma chave de API (enviada via Header) é válida
func (a *App) validateKeyHandler(w http.ResponseWriter, r *http.Request) {
	// Extrai a chave do header "Authorization: Bearer <key>"
	authHeader := r.Header.Get("Authorization")
	keyString := strings.TrimPrefix(authHeader, "Bearer ")

	if keyString == "" {
		http.Error(w, "Authorization header não encontrado", http.StatusUnauthorized)
		return
	}

	// Calcula o hash da chave recebida
	keyHash := hashAPIKey(keyString)

	// Verifica se o hash existe no banco de dados
	var id int
	dbCtx, span := a.dbSpan(r.Context(), "SELECT")
	err := a.DB.QueryRowContext(dbCtx, "SELECT id FROM api_keys WHERE key_hash = $1 AND is_active = true", keyHash).Scan(&id)
	if err != nil && err != sql.ErrNoRows {
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha na consulta")
	}
	span.End()
	if err != nil {
		// Se não encontrar (sql.ErrNoRows), ou qualquer outro erro, a chave é inválida
		logCtx(r.Context(), "Falha na validação da chave (hash: %s...): %v", keyHash[:6], err)
		http.Error(w, "Chave de API inválida ou inativa", http.StatusUnauthorized)
		return
	}

	// Chave válida
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Chave válida"})
}

// createKeyHandler cria uma nova chave de API
func (a *App) createKeyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Método não permitido", http.StatusMethodNotAllowed)
		return
	}

	var req CreateKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Corpo da requisição inválido", http.StatusBadRequest)
		return
	}

	if req.Name == "" {
		http.Error(w, "O campo 'name' é obrigatório", http.StatusBadRequest)
		return
	}

	// Gera uma nova chave e seu hash
	newKey, err := generateAPIKey()
	if err != nil {
		http.Error(w, "Erro ao gerar a chave", http.StatusInternalServerError)
		return
	}
	newKeyHash := hashAPIKey(newKey)

	// Salva o hash no banco de dados
	var newID int
	dbCtx, span := a.dbSpan(r.Context(), "INSERT")
	err = a.DB.QueryRowContext(dbCtx,
		"INSERT INTO api_keys (name, key_hash) VALUES ($1, $2) RETURNING id",
		req.Name, newKeyHash,
	).Scan(&newID)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha na gravação")
	}
	span.End()

	if err != nil {
		logCtx(r.Context(), "Erro ao salvar a chave no banco: %v", err)
		http.Error(w, "Erro ao salvar a chave", http.StatusInternalServerError)
		return
	}

	logCtx(r.Context(), "Nova chave criada com sucesso (ID: %d, Name: %s)", newID, req.Name)
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(CreateKeyResponse{
		Name:    req.Name,
		Key:     newKey, // Retorna a chave em texto plano pela última vez
		Message: "Guarde esta chave com segurança! Você não poderá vê-la novamente.",
	})
}

// --- Middleware ---

// masterKeyAuthMiddleware protege endpoints que só podem ser acessados com a MASTER_KEY
func (a *App) masterKeyAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		keyString := strings.TrimPrefix(authHeader, "Bearer ")

		if keyString != a.MasterKey {
			http.Error(w, "Acesso não autorizado", http.StatusForbidden)
			return
		}
		// Se a chave for válida, continua para o handler principal
		next.ServeHTTP(w, r)
	})
}

// seedLocalAPIKey garante uma chave fixa para integrações locais do compose.
func seedLocalAPIKey(db *sql.DB, name, plainKey string) error {
	keyHash := hashAPIKey(plainKey)

	_, err := db.Exec(
		`INSERT INTO api_keys (name, key_hash, is_active)
		 VALUES ($1, $2, true)
		 ON CONFLICT (key_hash)
		 DO UPDATE SET name = EXCLUDED.name, is_active = true`,
		name, keyHash,
	)
	if err != nil {
		log.Printf("Falha ao semear a chave local '%s': %v", name, err)
	}
	return err
}

// ensureAuthSchema cria a tabela do auth-service caso a base tenha sido iniciada sem os scripts.
func ensureAuthSchema(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS api_keys (
			id SERIAL PRIMARY KEY,
			name VARCHAR(100) NOT NULL,
			key_hash VARCHAR(64) NOT NULL UNIQUE,
			is_active BOOLEAN DEFAULT true,
			created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
		)
	`)
	if err != nil {
		log.Printf("Falha ao garantir schema do auth-service: %v", err)
	}
	return err
}
