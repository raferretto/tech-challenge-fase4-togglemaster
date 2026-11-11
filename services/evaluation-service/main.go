package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	"github.com/go-redis/redis/v8"
	"github.com/joho/godotenv"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Contexto de inicialização (fora de requisições)
var ctx = context.Background()

// App struct para injeção de dependência
type App struct {
	RedisClient         *redis.Client
	SqsSvc              *sqs.SQS
	SqsQueueURL         string
	HttpClient          *http.Client
	FlagServiceURL      string
	TargetingServiceURL string
	Tel                 *Telemetry
}

// Rotas registradas (usadas para normalizar o atributo http.route)
var routes = []string{"/evaluate"}

func main() {
	_ = godotenv.Load() // Carrega .env para dev local

	// --- Observabilidade (OpenTelemetry) ---
	tel, err := initTelemetry(ctx, "evaluation-service")
	if err != nil {
		log.Printf("Aviso: telemetria não inicializada por completo: %v", err)
	}

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}

	awsRegion := os.Getenv("AWS_REGION")
	if awsRegion == "" {
		awsRegion = "us-east-1"
	}

	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Fatal("REDIS_URL deve ser definida (ex: redis://localhost:6379)")
	}

	flagSvcURL := os.Getenv("FLAG_SERVICE_URL")
	if flagSvcURL == "" {
		log.Fatal("FLAG_SERVICE_URL deve ser definida")
	}

	targetingSvcURL := os.Getenv("TARGETING_SERVICE_URL")
	if targetingSvcURL == "" {
		log.Fatal("TARGETING_SERVICE_URL deve ser definida")
	}

	// SQS é opcional no dev local, mas obrigatório em prod.
	// Aceita AWS_SQS_URL ou SQS_QUEUE_URL (nome usado nos Secrets do cluster).
	sqsQueueURL := os.Getenv("AWS_SQS_URL")
	if sqsQueueURL == "" {
		sqsQueueURL = os.Getenv("SQS_QUEUE_URL")
	}
	sqsEndpointURL := os.Getenv("AWS_SQS_ENDPOINT_URL")
	if sqsQueueURL == "" {
		log.Println("Atenção: AWS_SQS_URL não definida. Eventos não serão enviados.")
	}

	// --- Inicializa Clientes ---

	// Cliente Redis
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("Não foi possível parsear a URL do Redis: %v", err)
	}
	rdb := redis.NewClient(opt)
	if _, err := rdb.Ping(ctx).Result(); err != nil {
		log.Fatalf("Não foi possível conectar ao Redis: %v", err)
	}
	log.Println("Conectado ao Redis com sucesso!")

	// Cliente SQS (AWS SDK)
	var sqsSvc *sqs.SQS
	if sqsQueueURL != "" {
		awsConfig := &aws.Config{
			Region: aws.String(awsRegion),
		}
		if sqsEndpointURL != "" {
			awsConfig.Endpoint = aws.String(sqsEndpointURL)
			awsConfig.DisableSSL = aws.Bool(true)
		}

		sess, err := session.NewSession(awsConfig)
		if err != nil {
			log.Fatalf("Não foi possível criar sessão AWS: %v", err)
		}
		sqsSvc = sqs.New(sess)
		log.Println("Cliente SQS inicializado com sucesso.")
	}

	// Cliente HTTP (com timeout). O transporte do otelhttp cria os spans de
	// cliente e propaga o contexto (traceparent) para flag e targeting.
	httpClient := &http.Client{
		Timeout:   5 * time.Second,
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}

	// Cria a instância da App
	app := &App{
		RedisClient:         rdb,
		SqsSvc:              sqsSvc,
		SqsQueueURL:         sqsQueueURL,
		HttpClient:          httpClient,
		FlagServiceURL:      flagSvcURL,
		TargetingServiceURL: targetingSvcURL,
		Tel:                 tel,
	}

	// --- Rotas ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/evaluate", app.evaluationHandler)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           tel.instrumentHTTP(mux, routes),
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Encerramento gracioso: no SIGTERM (ex.: rollout restart) o servidor para
	// de aceitar conexões e a telemetria pendente é enviada ao Collector.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		log.Println("Sinal de término recebido; encerrando o serviço...")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("Serviço de Avaliação (Go) rodando na porta %s", port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}

	flushCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := tel.shutdown(flushCtx); err != nil {
		log.Printf("Erro ao finalizar a telemetria: %v", err)
	}
}
