# Demonstração em vídeo (até 25 minutos)

Antes de gravar: ambiente no ar, `04-port-forward.sh` aberto, dados criados
(`05-seed-demo-data.sh`) e a carga rodando há pelo menos 5 minutos (`06-generate-load.sh`).
Abas abertas: ArgoCD, Grafana (dashboard, Explore e Alerting), New Relic, PagerDuty e Slack.

| # | Bloco | Tempo | O que mostrar |
|---|---|---|---|
| 1 | Visão geral | 3 min | `terraform output` (infra como código); `kubectl get nodes`; ArgoCD com as 12 Applications Synced/Healthy; `kubectl -n observability get pods` |
| 2 | Métricas, logs e OTel | 6 min | Dashboard do Grafana (recursos do cluster, requisições, erros, latência, fila SQS, logs); Explore → Loki com `{service_name="evaluation-service"}`; arquivo `20-gateway-config.yaml` explicando receivers → processors → exporters (métricas → Prometheus, logs → Loki, traces → New Relic) |
| 3 | APM e tracing | 4 min | New Relic: Service map com os 5 serviços; `curl` em `/evaluate`; trace distribuído com os spans de flag, targeting, auth, Redis e SQS/analytics |
| 4 | Incidente e Self-Healing | 9 min | `07-inject-failure.sh`; respostas 503 na carga; alerta Pending → Firing; incidente no PagerDuty; mensagem no Slack; log do Self-Healing; pods sendo substituídos; respostas 200; alerta resolvido |
| 5 | Fechamento | 2 min | Justificativas (arquitetura do OTel, New Relic, PagerDuty) e links |

## Comandos do bloco 4

```bash
# Terminal A
kubectl -n togglemaster get pods -l app=evaluation-service -w
# Terminal B
kubectl -n observability logs -f deployment/self-healing
# Terminal C
./scripts/fase4/07-inject-failure.sh
```

A regra espera 2 minutos antes de disparar: use esse intervalo para explicar o fluxo
(alerta → PagerDuty/Slack → webhook assinado → rollout restart) e as salvaguardas da automação.
