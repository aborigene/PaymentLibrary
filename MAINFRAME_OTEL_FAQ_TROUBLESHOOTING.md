# FAQ e Troubleshooting: OpenTelemetry no Mainframe

## Perguntas Frequentes (FAQ)

### Geral

#### P: Por que usar OpenTelemetry no mainframe?

**R:** OpenTelemetry oferece:
- **Padronização**: Protocolo único para traces, métricas e logs
- **Vendor-neutral**: Não há lock-in com fornecedores específicos
- **Integração**: Conecta mainframe com arquiteturas modernas (cloud, microservices)
- **Comunidade**: Suporte ativo e crescente
- **Futuro**: Padrão CNCF com adoção crescente na indústria

#### P: OpenTelemetry funciona bem em ambientes mainframe?

**R:** Sim, com considerações:
- ✅ **Java SDK funciona nativamente** no z/OS
- ✅ **Overhead mínimo** (~1-5% CPU, 256MB RAM)
- ✅ **Compatível com JES2/JES3**
- ⚠️ **COBOL requer bridge** via JNI (adiciona complexidade)
- ⚠️ **Network latency** deve ser considerada (use batching)

#### P: Qual a diferença entre instrumentar no mainframe vs. usar SMF?

**R:** 

| Aspecto | Instrumentação Direta | SMF + Conversão |
|---------|----------------------|-----------------|
| **Latência** | Tempo real (segundos) | Batch (minutos/horas) |
| **Granularidade** | Alta (código level) | Média (job/step level) |
| **Overhead** | Moderado (5%) | Baixo (1%) |
| **Customização** | Alta | Limitada |
| **Melhor para** | Debugging, APM | Compliance, auditing |

**Recomendação**: Use ambos! Instrumentação para tempo real, SMF para histórico.

### Implementação

#### P: Qual linguagem devo usar para instrumentação?

**R:**

1. **Java**: ⭐⭐⭐⭐⭐
   - SDK completo nativo
   - Auto-instrumentação disponível
   - Melhor suporte

2. **COBOL (via JNI)**: ⭐⭐⭐
   - Possível mas mais complexo
   - Requer bridge Java
   - Bom para legacy

3. **Assembler**: ⭐⭐
   - Muito baixo nível
   - Não recomendado
   - Use Java wrapper

4. **Rexx**: ⭐⭐
   - Via subprocess Java
   - Limitado

**Recomendação**: Use Java para nova instrumentação, crie bridges para legacy.

#### P: Preciso modificar todos os meus jobs?

**R:** Não! Estratégias progressivas:

1. **Fase 1**: SMF to OpenTelemetry converter (sem mudanças em jobs)
2. **Fase 2**: Instrumentar jobs críticos
3. **Fase 3**: Auto-instrumentação via JVM agent
4. **Fase 4**: Instrumentação completa

#### P: Como lidar com jobs de longa duração?

**R:**

```java
// Para jobs que rodam por horas/dias
public void monitorLongRunningJob() {
    Span jobSpan = tracer.spanBuilder("long.running.job")
        .startSpan();
    
    try (Scope scope = jobSpan.makeCurrent()) {
        // Criar spans intermediários a cada checkpoint
        for (int i = 0; i < totalSteps; i++) {
            Span checkpointSpan = tracer.spanBuilder("checkpoint")
                .setAttribute("checkpoint.number", i)
                .startSpan();
            
            try {
                processStep(i);
                checkpointSpan.setStatus(StatusCode.OK);
            } finally {
                checkpointSpan.end();  // Exporta imediatamente
            }
            
            // Flush periódico
            if (i % 100 == 0) {
                forceFlush();
            }
        }
    } finally {
        jobSpan.end();
    }
}
```

### Conectividade

#### P: O mainframe precisa de acesso direto à internet?

**R:** Não! Opções:

1. **Collector interno**: Mainframe → Collector on-premise → Internet
2. **MQ**: Mainframe → IBM MQ → Collector
3. **File transfer**: Mainframe → Shared disk → Collector
4. **Proxy**: Mainframe → HTTP Proxy → Collector

**Recomendação**: Use collector interno (opção 1).

#### P: Como configurar firewall?

**R:**

```bash
# Regras necessárias (iptables)

# Permitir saída do mainframe para collector (OTLP gRPC)
iptables -A OUTPUT -p tcp --dport 4317 -d <collector-ip> -j ACCEPT

# Permitir saída para OTLP HTTP (alternativa)
iptables -A OUTPUT -p tcp --dport 4318 -d <collector-ip> -j ACCEPT

# Para z/OS firewall (AT-TLS rules)
# Ver MAINFRAME_JES_OPENTELEMETRY_MONITORING.md seção "Configuração de Rede"
```

#### P: Como garantir que dados não se percam se o collector cair?

**R:** Implementar persistência:

```java
// Configurar disk queue
OtlpGrpcSpanExporter exporter = OtlpGrpcSpanExporter.builder()
    .setEndpoint("http://collector:4317")
    .build();

// Wrapper com fallback
SpanExporter resilientExporter = new ResilientExporter(
    exporter,
    new DiskBackedQueue("/u/otel/queue", 100_000_000) // 100MB
);
```

### Performance

#### P: Qual o overhead de OpenTelemetry?

**R:** Medições típicas:

- **CPU**: 1-5% (depende de sampling)
- **Memória**: 256-512 MB (depende de buffer)
- **Rede**: 1-10 Mbps (depende de volume)
- **Latência**: < 1ms por span (local)

**Para minimizar**:
```java
// Use sampling
Sampler sampler = Sampler.parentBased(
    Sampler.traceIdRatioBased(0.1)  // 10% sampling
);

// Use batching
BatchSpanProcessor processor = BatchSpanProcessor.builder(exporter)
    .setScheduleDelay(Duration.ofSeconds(10))
    .setMaxQueueSize(2048)
    .build();
```

#### P: Quantos spans meu mainframe vai gerar?

**R:** Estimativa:

- **Job simples**: 5-20 spans
- **Job médio**: 50-100 spans
- **Job complexo**: 500+ spans

**Cálculo**:
```
Jobs/dia: 10,000
Spans/job médio: 50
Total spans/dia: 500,000
Spans/segundo: ~6

Com overhead: ~50KB/span
Rede/dia: ~25GB
Rede/segundo: ~300KB/s (2.4 Mbps)
```

### Segurança

#### P: Como proteger dados sensíveis?

**R:**

```java
// 1. Redação automática
public class SecureSpanProcessor implements SpanProcessor {
    @Override
    public void onStart(Context context, ReadWriteSpan span) {
        span.getAttributes().forEach((key, value) -> {
            if (key.getKey().contains("password") || 
                key.getKey().contains("card")) {
                span.setAttribute(key, "***REDACTED***");
            }
        });
    }
}

// 2. Criptografia em trânsito
OtlpGrpcSpanExporter.builder()
    .setEndpoint("https://collector:4317")
    .setTrustedCertificates(loadCerts())
    .build();

// 3. Filtros no collector
processors:
  attributes:
    actions:
      - key: credit_card
        action: delete
      - key: password
        action: delete
```

#### P: Preciso de certificados especiais?

**R:** Sim, para produção:

```bash
# Gerar certificados (exemplo com OpenSSL)

# CA certificate
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt

# Server certificate (collector)
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -out server.crt

# Client certificate (mainframe)
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr
openssl x509 -req -days 365 -in client.csr -CA ca.crt -CAkey ca.key -out client.crt

# Converter para formato z/OS (PKCS12)
openssl pkcs12 -export -out client.p12 -inkey client.key -in client.crt -certfile ca.crt
```

### Integração

#### P: Como correlacionar traces entre mainframe e aplicações web?

**R:**

```java
// No mainframe: extrair contexto
W3CTraceContextPropagator propagator = 
    W3CTraceContextPropagator.getInstance();

Map<String, String> carrier = new HashMap<>();
propagator.inject(Context.current(), carrier, 
    (c, key, value) -> c.put(key, value));

// Passar no HTTP header ou MQ message
httpRequest.setHeader("traceparent", carrier.get("traceparent"));
mqMessage.setStringProperty("traceparent", carrier.get("traceparent"));

// Na aplicação web: injetar contexto
Context extractedContext = propagator.extract(
    Context.current(), 
    httpHeaders, 
    (headers, key) -> headers.get(key)
);

Span span = tracer.spanBuilder("web.request")
    .setParent(extractedContext)
    .startSpan();
```

#### P: Funciona com CICS?

**R:** Sim! Exemplo:

```java
// CICSTransactionMonitor.java
public class CICSTransactionMonitor {
    
    public void monitorTransaction() {
        // Obter informações da transação via JCICS
        Task task = Task.getTask();
        
        Span span = tracer.spanBuilder("cics.transaction")
            .setAttribute("transaction.id", task.getTransactionName())
            .setAttribute("terminal.id", task.getPrincipalFacility().getName())
            .setAttribute("user.id", task.getUSERID())
            .startSpan();
            
        try (Scope scope = span.makeCurrent()) {
            // Código da transação...
        } finally {
            span.end();
        }
    }
}
```

## Troubleshooting

### Problema 1: Spans não aparecem no backend

#### Sintomas
- Job executa sem erros
- Nenhum trace visível no Dynatrace/Jaeger
- Logs não mostram problemas óbvios

#### Diagnóstico

```bash
# 1. Verificar se SDK está inicializado
grep "OpenTelemetry" /u/otel/logs/job.log

# 2. Verificar conectividade
telnet otel-collector 4317

# 3. Verificar se spans estão sendo criados
grep "SpanData" /u/otel/logs/debug.log

# 4. Verificar collector
curl http://collector:8888/metrics | grep received_spans

# 5. Testar manualmente
curl -X POST http://collector:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d @test-span.json
```

#### Soluções

**Se SDK não inicializa:**
```java
// Adicionar inicialização explícita
OpenTelemetrySdk sdk = AutoConfiguredOpenTelemetrySdk.initialize()
    .getOpenTelemetrySdk();

// Verificar variáveis de ambiente
System.getenv().forEach((k, v) -> {
    if (k.startsWith("OTEL_")) {
        System.out.println(k + "=" + v);
    }
});
```

**Se rede não funciona:**
```bash
# Verificar rotas
netstat -rn

# Verificar DNS
nslookup otel-collector

# Testar com IP direto
-Dotel.exporter.otlp.endpoint=http://10.20.30.40:4317
```

**Se collector não recebe:**
```yaml
# Aumentar log level
service:
  telemetry:
    logs:
      level: debug

# Verificar receivers
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317  # NÃO use localhost!
```

### Problema 2: Performance degradada

#### Sintomas
- Jobs mais lentos após instrumentação
- Alto uso de CPU
- Memória crescendo

#### Diagnóstico

```bash
# Verificar uso de recursos
top -p $(pgrep -f "java.*otel")

# Verificar tamanho da fila
jcmd <pid> VM.native_memory summary | grep "Internal"

# Verificar GC
jstat -gc <pid> 1000
```

#### Soluções

**Reduzir sampling:**
```java
Sampler sampler = Sampler.traceIdRatioBased(0.1);  // 10% em vez de 100%
```

**Otimizar batch:**
```java
BatchSpanProcessor.builder(exporter)
    .setScheduleDelay(Duration.ofSeconds(30))  // Aumentar de 10s
    .setMaxQueueSize(512)  // Reduzir de 2048
    .setMaxExportBatchSize(128)  // Reduzir de 512
    .build();
```

**Aumentar memória:**
```jcl
//JAVAJVM DD *
-Xms512m
-Xmx1024m
-XX:MaxMetaspaceSize=256m
/*
```

### Problema 3: Certificados TLS

#### Sintomas
- `SSLHandshakeException`
- `PKIX path building failed`
- Connection refused

#### Diagnóstico

```bash
# Testar conexão TLS
openssl s_client -connect collector:4317 -showcerts

# Verificar certificado
openssl x509 -in /etc/otel/certs/ca.crt -text -noout

# Verificar keystore Java
keytool -list -keystore /u/otel/truststore.jks
```

#### Soluções

**Importar certificado CA:**
```bash
# Importar para truststore Java
keytool -import -alias otel-ca \
    -file /etc/otel/certs/ca.crt \
    -keystore /u/otel/truststore.jks \
    -storepass changeit

# Usar truststore
-Djavax.net.ssl.trustStore=/u/otel/truststore.jks
-Djavax.net.ssl.trustStorePassword=changeit
```

**Ou desabilitar verificação (APENAS TESTE!):**
```java
OtlpGrpcSpanExporter.builder()
    .setEndpoint("http://collector:4317")  // http em vez de https
    .build();
```

### Problema 4: Dados corrompidos ou incompletos

#### Sintomas
- Spans sem atributos
- Trace context perdido
- Timestamps incorretos

#### Diagnóstico

```java
// Adicionar logging detalhado
public class DebugSpanProcessor implements SpanProcessor {
    @Override
    public void onStart(Context context, ReadWriteSpan span) {
        System.out.println("Span started: " + span.getName());
        System.out.println("Context: " + context);
    }
    
    @Override
    public void onEnd(ReadableSpan span) {
        System.out.println("Span ended: " + span.getName());
        System.out.println("Attributes: " + span.getAttributes());
        System.out.println("Duration: " + 
            (span.getEndEpochNanos() - span.getStartEpochNanos()) / 1_000_000 + "ms");
    }
}
```

#### Soluções

**Garantir contexto correto:**
```java
// SEMPRE usar try-with-resources
try (Scope scope = span.makeCurrent()) {
    // Código aqui terá contexto correto
}
```

**Adicionar atributos antes de finalizar:**
```java
span.setAttribute("key", "value");  // ANTES
span.end();  // Não adicionar atributos depois!
```

**Corrigir timezone:**
```java
// z/OS pode ter timezone diferente
System.setProperty("user.timezone", "America/Sao_Paulo");
```

### Problema 5: Collector está dropando spans

#### Sintomas
- `dropped_spans` métrica > 0
- `queue_size` chegando ao limite
- Mensagens "queue is full"

#### Diagnóstico

```bash
# Verificar métricas do collector
curl http://collector:8888/metrics | grep -E "(dropped|queue)"

# Saída esperada:
# otelcol_processor_dropped_spans 0
# otelcol_exporter_queue_size 100
# otelcol_exporter_queue_capacity 1000
```

#### Soluções

**Aumentar capacidade:**
```yaml
processors:
  batch:
    timeout: 5s  # Reduzir para exportar mais rápido
    send_batch_size: 2000  # Aumentar batch

exporters:
  otlp:
    sending_queue:
      queue_size: 10000  # Aumentar de 1000
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
```

**Adicionar buffer secundário:**
```yaml
exporters:
  file:  # Backup para disco
    path: /var/log/otel/backup
    
service:
  pipelines:
    traces:
      exporters: [otlphttp/dynatrace, file]  # Exportar para ambos
```

**Escalar collector:**
```yaml
# Usar múltiplos collectors com load balancer
processors:
  loadbalancing:
    resolver:
      static:
        hostnames:
          - collector-1:4317
          - collector-2:4317
          - collector-3:4317
```

## Ferramentas de Diagnóstico

### Script de Health Check

```bash
#!/bin/bash
# otel-healthcheck.sh

echo "=== OpenTelemetry Mainframe Health Check ==="

# 1. Verificar processo Java
echo -e "\n1. Java Process:"
ps -ef | grep opentelemetry-javaagent || echo "❌ Agent não encontrado"

# 2. Verificar conectividade
echo -e "\n2. Network Connectivity:"
nc -zv otel-collector 4317 2>&1 | grep -q succeeded && echo "✅ gRPC OK" || echo "❌ gRPC failed"
nc -zv otel-collector 4318 2>&1 | grep -q succeeded && echo "✅ HTTP OK" || echo "❌ HTTP failed"

# 3. Verificar disk queue
echo -e "\n3. Disk Queue:"
du -sh /u/otel/queue
ls -l /u/otel/queue/*.bin 2>/dev/null | wc -l | xargs echo "Files in queue:"

# 4. Verificar logs
echo -e "\n4. Recent Errors:"
tail -100 /u/otel/logs/*.log | grep -i "error\|exception" | tail -5

# 5. Verificar collector
echo -e "\n5. Collector Metrics:"
curl -s http://otel-collector:8888/metrics 2>/dev/null | grep -E "received_spans|dropped_spans" || echo "❌ Collector não acessível"

# 6. Test span
echo -e "\n6. Sending Test Span:"
curl -X POST http://otel-collector:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "healthcheck"}}]},
      "scopeSpans": [{
        "spans": [{
          "traceId": "00000000000000000000000000000001",
          "spanId": "0000000000000001",
          "name": "healthcheck",
          "kind": 1,
          "startTimeUnixNano": '"$(date +%s)000000000"',
          "endTimeUnixNano": '"$(date +%s)000000000"'
        }]
      }]
    }]
  }' 2>&1 | grep -q "200\|202" && echo "✅ Test span sent" || echo "❌ Test span failed"

echo -e "\n=== Health Check Complete ==="
```

### Monitoramento Contínuo

```yaml
# prometheus-alerts.yml
groups:
  - name: mainframe-otel
    interval: 30s
    rules:
      - alert: MainframeSpansDropped
        expr: rate(otelcol_processor_dropped_spans{source="mainframe"}[5m]) > 0
        annotations:
          summary: "Mainframe spans sendo descartados"
          
      - alert: MainframeDiskQueueGrowing
        expr: rate(mainframe_otel_queue_size_bytes[5m]) > 0
        for: 15m
        annotations:
          summary: "Disk queue do mainframe crescendo"
          
      - alert: MainframeExporterDown
        expr: up{job="mainframe-exporter"} == 0
        for: 2m
        annotations:
          summary: "Exportador do mainframe está down"
```

## Recursos Adicionais

### Links Úteis

- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
- [Java Instrumentation](https://opentelemetry.io/docs/instrumentation/java/)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)
- [IBM z/OS Java](https://www.ibm.com/docs/en/sdk-java-technology)

### Comunidade

- [CNCF Slack #otel](https://cloud-native.slack.com)
- [OpenTelemetry GitHub](https://github.com/open-telemetry)
- [Stack Overflow Tag: opentelemetry](https://stackoverflow.com/questions/tagged/opentelemetry)

### Suporte Comercial

- IBM Support (z/OS issues)
- Dynatrace Support (Dynatrace integration)
- CNCF Commercial Support Partners

---

**Última Atualização**: Novembro 2024  
**Versão**: 1.0
