import os
import sys
import threading
import json
import uuid
import time
import logging
import boto3
from botocore.exceptions import NoCredentialsError, ClientError
from flask import Flask, jsonify
from dotenv import load_dotenv
from opentelemetry.trace import SpanKind, Status, StatusCode

import telemetry

# Carrega .env para desenvolvimento local
load_dotenv()

# Observabilidade (Fase 4): logs com trace_id/span_id, traces e métricas (OpenTelemetry)
telemetry.init("analytics-service")
log = logging.getLogger(__name__)

events_processed = telemetry.meter().create_counter(
    "togglemaster.analytics.events.processed", unit="{event}",
    description="Eventos de avaliação consumidos da fila SQS, por resultado")
processing_duration = telemetry.meter().create_histogram(
    "togglemaster.analytics.processing.duration", unit="s",
    description="Duração do processamento de cada evento consumido",
    explicit_bucket_boundaries_advisory=telemetry.DURATION_BUCKETS)

# --- Configuração ---
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("AWS_SQS_URL") or os.getenv("SQS_QUEUE_URL")
DYNAMODB_ENDPOINT_URL = os.getenv("AWS_DYNAMODB_ENDPOINT_URL")
SQS_ENDPOINT_URL = os.getenv("AWS_SQS_ENDPOINT_URL")
DYNAMODB_TABLE_NAME = os.getenv("AWS_DYNAMODB_TABLE") or os.getenv("DYNAMODB_TABLE")

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical("Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.")
    sys.exit(1)

# --- Clientes Boto3 ---
# Criamos a sessão uma vez
try:
    session = boto3.Session(region_name=AWS_REGION)
    sqs_client = session.client("sqs", endpoint_url=SQS_ENDPOINT_URL) if SQS_ENDPOINT_URL else session.client("sqs")
    dynamodb_client = session.client("dynamodb", endpoint_url=DYNAMODB_ENDPOINT_URL) if DYNAMODB_ENDPOINT_URL else session.client("dynamodb")
    log.info(f"Clientes Boto3 inicializados na região {AWS_REGION}")
    if SQS_ENDPOINT_URL:
        log.info(f"SQS local configurado em {SQS_ENDPOINT_URL}")
    if DYNAMODB_ENDPOINT_URL:
        log.info(f"DynamoDB local configurado em {DYNAMODB_ENDPOINT_URL}")
except NoCredentialsError:
    log.critical("Credenciais da AWS não encontradas. Verifique seu ambiente.")
    sys.exit(1)
except Exception as e:
    log.critical(f"Erro ao inicializar o Boto3: {e}")
    sys.exit(1)


# --- SQS Worker ---

def _trace_carrier(message):
    """Converte os MessageAttributes (tipo String) em um dicionário para o propagador."""
    attributes = message.get('MessageAttributes') or {}
    return {key: value.get('StringValue', '') for key, value in attributes.items()}


def process_message(message):
    """ Processa uma única mensagem SQS e a insere no DynamoDB """
    # O contexto de rastreamento (traceparent) vem do evaluation-service nos
    # atributos da mensagem: o span CONSUMER continua o mesmo trace da requisição.
    parent_context = telemetry.extract_context(_trace_carrier(message))
    start = time.perf_counter()
    result = "success"

    with telemetry.tracer().start_as_current_span(
        "process ToggleMasterEvents", context=parent_context, kind=SpanKind.CONSUMER,
        attributes={
            "messaging.system": "aws_sqs",
            "messaging.operation.type": "process",
            "messaging.destination.name": "ToggleMasterEvents",
        },
    ) as span:
        try:
            log.info(f"Processando mensagem ID: {message['MessageId']}")
            body = json.loads(message['Body'])

            # Gera um ID único para o item no DynamoDB
            event_id = str(uuid.uuid4())

            # Constrói o item no formato do DynamoDB
            item = {
                'event_id': {'S': event_id},
                'user_id': {'S': body['user_id']},
                'flag_name': {'S': body['flag_name']},
                'result': {'BOOL': body['result']},
                'timestamp': {'S': body['timestamp']}
            }

            # Insere no DynamoDB
            with telemetry.tracer().start_as_current_span(
                "DynamoDB PutItem", kind=SpanKind.CLIENT,
                attributes={"db.system.name": "aws.dynamodb", "db.operation.name": "PutItem",
                            "db.collection.name": DYNAMODB_TABLE_NAME},
            ):
                dynamodb_client.put_item(
                    TableName=DYNAMODB_TABLE_NAME,
                    Item=item
                )

            log.info(f"Evento {event_id} (Flag: {body['flag_name']}) salvo no DynamoDB.")

            # Se tudo deu certo, deleta a mensagem da fila
            sqs_client.delete_message(
                QueueUrl=SQS_QUEUE_URL,
                ReceiptHandle=message['ReceiptHandle']
            )

        except json.JSONDecodeError:
            result = "invalid_message"
            log.error(f"Erro ao decodificar JSON da mensagem ID: {message['MessageId']}")
            # Não deleta a mensagem, pode ser uma "poison pill"
        except ClientError as e:
            result = "error"
            span.record_exception(e)
            log.error(f"Erro do Boto3 (DynamoDB ou SQS) ao processar {message['MessageId']}: {e}")
            # Não deleta a mensagem, tenta novamente
        except Exception as e:
            result = "error"
            span.record_exception(e)
            log.error(f"Erro inesperado ao processar {message['MessageId']}: {e}")
            # Não deleta a mensagem, tenta novamente
        finally:
            if result != "success":
                span.set_status(Status(StatusCode.ERROR, result))
            events_processed.add(1, {"result": result})
            processing_duration.record(time.perf_counter() - start, {"result": result})


def sqs_worker_loop():
    """ Loop principal do worker que ouve a fila SQS """
    log.info("Iniciando o worker SQS...")
    while True:
        try:
            # Long-polling: espera até 20s por mensagens
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,  # Processa em lotes de até 10
                WaitTimeSeconds=20,
                MessageAttributeNames=['All']  # inclui o traceparent propagado
            )
            
            messages = response.get('Messages', [])
            if not messages:
                # Nenhuma mensagem, continua o loop
                continue
                
            log.info(f"Recebidas {len(messages)} mensagens.")
            
            for message in messages:
                process_message(message)
                
        except ClientError as e:
            log.error(f"Erro do Boto3 no loop principal do SQS: {e}")
            time.sleep(10) # Pausa antes de tentar novamente
        except Exception as e:
            log.error(f"Erro inesperado no loop principal do SQS: {e}")
            time.sleep(10)

# --- Servidor Flask (Apenas para Health Check) ---

app = Flask(__name__)
telemetry.instrument_flask(app)

@app.route('/health')
def health():
    # Uma verificação de saúde real poderia checar a conexão com o DynamoDB/SQS
    return jsonify({"status": "ok"})

# --- Inicialização ---

def start_worker():
    """ Inicia o worker SQS em uma thread separada """
    worker_thread = threading.Thread(target=sqs_worker_loop, daemon=True)
    worker_thread.start()

# Inicia o worker SQS em uma thread de background
# Isso garante que ele inicie tanto com 'flask run' quanto com 'gunicorn'
start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8005))
    app.run(host='0.0.0.0', port=port, debug=False)  # nosec B104
