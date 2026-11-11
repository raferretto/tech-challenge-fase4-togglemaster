package main

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
)

// App struct (para injeção de dependência)
type App struct {
	DB        *sql.DB
	MasterKey string
	Tel       *Telemetry
}

// Rotas registradas (usadas para normalizar o atributo http.route)
var routes = []string{"/validate", "/admin/keys"}

func main() {
	// Carrega o .env para desenvolvimento local. Em produção, isso não fará nada.
	_ = godotenv.Load()

	// --- Observabilidade (OpenTelemetry) ---
	tel, err := initTelemetry(context.Background(), "auth-service")
	if err != nil {
		log.Printf("Aviso: telemetria não inicializada por completo: %v", err)
	}

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001" // Porta padrão
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL deve ser definida")
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY deve ser definida")
	}

	serviceAPIKey := os.Getenv("SERVICE_API_KEY")
	serviceAPIKeyName := os.Getenv("SERVICE_API_KEY_NAME")
	if serviceAPIKeyName == "" {
		serviceAPIKeyName = "evaluation-service-key"
	}

	// --- Conexão com o Banco ---
	db, err := connectDB(databaseURL)
	if err != nil {
		log.Fatalf("Não foi possível conectar ao banco de dados: %v", err)
	}
	defer db.Close()

	if err := ensureAuthSchema(db); err != nil {
		log.Fatalf("Não foi possível garantir o schema local do auth-service: %v", err)
	}

	if serviceAPIKey != "" {
		if err := seedLocalAPIKey(db, serviceAPIKeyName, serviceAPIKey); err != nil {
			log.Fatalf("Não foi possível semear a chave local de serviço: %v", err)
		}
		log.Printf("Chave local de serviço semeada/atualizada: %s", serviceAPIKeyName)
	}

	app := &App{
		DB:        db,
		MasterKey: masterKey,
		Tel:       tel,
	}

	// --- Rotas da API ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)

	// Endpoint público para validar uma chave
	mux.HandleFunc("/validate", app.validateKeyHandler)

	// Endpoints de "admin" para criar/gerenciar chaves
	// Eles são protegidos pelo middleware de autenticação
	mux.Handle("/admin/keys", app.masterKeyAuthMiddleware(http.HandlerFunc(app.createKeyHandler)))

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           tel.instrumentHTTP(mux, routes),
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Encerramento gracioso: envia a telemetria pendente antes de sair.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		log.Println("Sinal de término recebido; encerrando o serviço...")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}

	flushCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := tel.shutdown(flushCtx); err != nil {
		log.Printf("Erro ao finalizar a telemetria: %v", err)
	}
}

// connectDB inicializa e testa a conexão com o PostgreSQL
func connectDB(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	if err = db.Ping(); err != nil {
		return nil, err
	}

	log.Println("Conectado ao PostgreSQL com sucesso!")
	return db, nil
}
