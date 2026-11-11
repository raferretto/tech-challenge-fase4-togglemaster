# Runbook — EvaluationServiceHighErrorRate

**Alerta:** mais de 20% das requisições ao `evaluation-service` retornaram HTTP 5xx nos últimos
5 minutos (mínimo de 20 requisições), por pelo menos 2 minutos.
**Severidade:** crítica — a avaliação de feature flags está indisponível para parte dos usuários.

## O que acontece automaticamente

1. O Grafana abre o incidente no PagerDuty e publica a notificação no Slack.
2. O Self-Healing recebe o webhook assinado e reinicia o deployment `evaluation-service`
   (substituição gradual dos pods).
3. Quando a taxa de erros volta ao normal, o alerta é resolvido e o incidente é fechado.

## Como acompanhar

```bash
# log da automação (o que foi feito e o resultado do rollout)
kubectl -n observability logs deployment/self-healing --tail=50

# pods do serviço (novos pods após o reinício)
kubectl -n togglemaster get pods -l app=evaluation-service -o wide
kubectl -n togglemaster rollout status deployment/evaluation-service
```

- Dashboard: Grafana → *ToggleMaster - Saúde do Ecossistema* (painéis de erros 5xx e
  requisições por código HTTP).
- Logs: Grafana → Explore → Loki → `{service_name="evaluation-service"} |= "ERRO"`.
- Traces: New Relic → Distributed tracing → filtre por `service.name = evaluation-service` e erros.

## Se o Self-Healing não resolver

O reinício só elimina falhas ligadas ao estado do próprio pod. Se os erros continuarem:

| Verifique | Comando |
|---|---|
| Dependências (flag e targeting respondendo) | `kubectl -n togglemaster get pods` e os painéis de erros por serviço |
| Erros do evaluation-service | `kubectl -n togglemaster logs deployment/evaluation-service --tail=100` |
| Redis e fila SQS | mensagens de erro de conexão nos logs acima |
| Último deploy | `kubectl -n togglemaster rollout history deployment/evaluation-service`; se o problema veio de uma versão nova, reverta o commit da imagem no repositório GitOps |
| Falha de laboratório ainda ativa | `./scripts/fase4/08-clear-failure.sh` |

O Self-Healing não age de novo na mesma ocorrência nem antes do intervalo mínimo de 5 minutos:
a partir daí a correção é manual, pela pessoa acionada no PagerDuty.
