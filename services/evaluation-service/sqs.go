package main

import (
	"context"
	"encoding/json"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"
)

// Evento que será enviado para a fila
type EvaluationEvent struct {
	UserID    string    `json:"user_id"`
	FlagName  string    `json:"flag_name"`
	Result    bool      `json:"result"`
	Timestamp time.Time `json:"timestamp"`
}

// sqsCarrier adapta os MessageAttributes do SQS ao propagador do
// OpenTelemetry: o contexto de rastreamento (traceparent/tracestate) viaja
// como atributos do tipo String e é extraído pelo analytics-service.
type sqsCarrier map[string]*sqs.MessageAttributeValue

func (c sqsCarrier) Get(key string) string {
	if v, ok := c[key]; ok && v.StringValue != nil {
		return *v.StringValue
	}
	return ""
}

func (c sqsCarrier) Set(key, value string) {
	c[key] = &sqs.MessageAttributeValue{
		DataType:    aws.String("String"),
		StringValue: aws.String(value),
	}
}

func (c sqsCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

// sendEvaluationEvent envia um evento para a fila SQS
func (a *App) sendEvaluationEvent(ctx context.Context, userID, flagName string, result bool) {
	// Se a URL da fila não foi configurada, apenas loga localmente e sai.
	if a.SqsSvc == nil || a.SqsQueueURL == "" {
		logCtx(ctx, "[SQS_DISABLED] Evento: User '%s', Flag '%s', Result '%t'", userID, flagName, result)
		return
	}

	// Span PRODUCER: representa a publicação da mensagem na fila.
	ctx, span := a.Tel.Tracer.Start(ctx, "send ToggleMasterEvents", trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			attribute.String("messaging.system", "aws_sqs"),
			attribute.String("messaging.operation.type", "send"),
			attribute.String("messaging.destination.name", "ToggleMasterEvents"),
		))
	defer span.End()

	outcome := "success"
	defer func() {
		a.Tel.sqsPublished.Add(ctx, 1, metric.WithAttributes(attribute.String("result", outcome)))
	}()

	event := EvaluationEvent{
		UserID:    userID,
		FlagName:  flagName,
		Result:    result,
		Timestamp: time.Now().UTC(),
	}

	body, err := json.Marshal(event)
	if err != nil {
		outcome = "error"
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha ao serializar o evento")
		logCtx(ctx, "Erro ao serializar evento SQS: %v", err)
		return
	}

	// Injeta o contexto de rastreamento nos atributos da mensagem
	attrs := sqsCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, attrs)

	// Envia a mensagem
	_, err = a.SqsSvc.SendMessageWithContext(ctx, &sqs.SendMessageInput{
		MessageBody:       aws.String(string(body)),
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageAttributes: attrs,
	})

	if err != nil {
		outcome = "error"
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha ao publicar no SQS")
		logCtx(ctx, "Erro ao enviar mensagem para SQS: %v", err)
	} else {
		logCtx(ctx, "Evento de avaliação enviado para SQS (Flag: %s)", flagName)
	}
}
