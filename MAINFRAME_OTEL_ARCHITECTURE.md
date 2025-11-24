# Arquitetura de Monitoramento OpenTelemetry para Mainframe

## Visão Geral da Arquitetura

Este documento detalha a arquitetura completa para implementação de monitoramento OpenTelemetry em ambientes mainframe z/OS com JES.

## Arquitetura em Camadas

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CAMADA 1: MAINFRAME z/OS                          │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    JES2/JES3 Subsystem                           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │   │
│  │  │  Job Queue   │  │ Job Execution│  │  Job Output  │         │   │
│  │  │  Management  │  │   & Steps    │  │   & Logs     │         │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │   │
│  └─────────┼──────────────────┼──────────────────┼────────────────┘   │
│            │                  │                  │                      │
│            └──────────────────┴──────────────────┘                      │
│                               │                                         │
│  ┌────────────────────────────▼─────────────────────────────────────┐ │
│  │              OpenTelemetry Instrumentation Layer                  │ │
│  │                                                                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │COBOL Bridge  │  │  Java SDK    │  │  Assembler   │          │ │
│  │  │   (via JNI)  │  │  (Native)    │  │    Bridge    │          │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │ │
│  │         │                  │                  │                   │ │
│  │         └──────────────────┴──────────────────┘                   │ │
│  │                            │                                       │ │
│  │  ┌─────────────────────────▼────────────────────────────────┐   │ │
│  │  │          OpenTelemetry SDK (Java on z/OS)                 │   │ │
│  │  │  - Tracer Provider                                        │   │ │
│  │  │  - Meter Provider                                         │   │ │
│  │  │  - Logger Provider                                        │   │ │
│  │  │  - Context Propagation                                    │   │ │
│  │  │  - Resource Detection                                     │   │ │
│  │  └───────────────────────┬───────────────────────────────────┘   │ │
│  └────────────────────────────┼───────────────────────────────────────┘ │
│                               │                                         │
│  ┌────────────────────────────▼─────────────────────────────────────┐ │
│  │              Data Processing & Buffering Layer                    │ │
│  │                                                                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │ Batch Span   │  │ Metric       │  │ Log          │          │ │
│  │  │ Processor    │  │ Aggregation  │  │ Processor    │          │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │ │
│  │         │                  │                  │                   │ │
│  │         └──────────────────┴──────────────────┘                   │ │
│  │                            │                                       │ │
│  │  ┌─────────────────────────▼────────────────────────────────┐   │ │
│  │  │              Memory Buffer / Disk Queue                   │   │ │
│  │  │  - In-memory ring buffer (default 2048 spans)            │   │ │
│  │  │  - Disk-backed queue for resilience                      │   │ │
│  │  │  - Compression: gzip                                      │   │ │
│  │  └───────────────────────┬───────────────────────────────────┘   │ │
│  └────────────────────────────┼───────────────────────────────────────┘ │
│                               │                                         │
│  ┌────────────────────────────▼─────────────────────────────────────┐ │
│  │                  Export Layer (Múltiplos Protocolos)             │ │
│  │                                                                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │OTLP/gRPC     │  │ OTLP/HTTP    │  │ IBM MQ       │          │ │
│  │  │Port 4317     │  │ Port 4318    │  │ Queue-based  │          │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │ │
│  │         │                  │                  │                   │ │
│  └─────────┼──────────────────┼──────────────────┼────────────────────┘ │
│            │                  │                  │                      │
└────────────┼──────────────────┼──────────────────┼──────────────────────┘
             │                  │                  │
             │   TCP/IP Stack   │                  │
             │   + AT-TLS       │                  │
             │                  │                  │
┌────────────▼──────────────────▼──────────────────▼──────────────────────┐
│                  CAMADA 2: NETWORK / FIREWALL                            │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  Network Security                                               │    │
│  │  - Firewall rules (allow 4317, 4318 outbound)                 │    │
│  │  - TLS 1.3 encryption                                          │    │
│  │  - Certificate validation                                       │    │
│  │  - Connection pooling                                           │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                           │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼───────────────────────────────────────┐
│              CAMADA 3: OPENTELEMETRY COLLECTOR TIER                       │
│                    (Linux/Windows/Kubernetes)                             │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Receiver Layer                               │    │
│  │                                                                  │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │    │
│  │  │ OTLP/gRPC    │  │ OTLP/HTTP    │  │ Filelog      │        │    │
│  │  │ Receiver     │  │ Receiver     │  │ (fallback)   │        │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │    │
│  │         └──────────────────┴──────────────────┘                 │    │
│  └───────────────────────────┬─────────────────────────────────────┘    │
│                               │                                           │
│  ┌────────────────────────────▼─────────────────────────────────────┐  │
│  │                    Processing Pipeline                            │  │
│  │                                                                    │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │  1. Resource Processor                                    │   │  │
│  │  │     - Enrich with collector metadata                      │   │  │
│  │  │     - Add environment labels                              │   │  │
│  │  └──────────────────────────────────────────────────────────┘   │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │  2. Batch Processor                                       │   │  │
│  │  │     - Aggregate spans/metrics                             │   │  │
│  │  │     - Optimize network usage                              │   │  │
│  │  └──────────────────────────────────────────────────────────┘   │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │  3. Filter Processor                                      │   │  │
│  │  │     - Drop test data                                      │   │  │
│  │  │     - Sample high-volume traces                           │   │  │
│  │  └──────────────────────────────────────────────────────────┘   │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │  4. Transform Processor                                   │   │  │
│  │  │     - Normalize attribute names                           │   │  │
│  │  │     - Redact sensitive data                               │   │  │
│  │  └──────────────────────────────────────────────────────────┘   │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │  5. Tail Sampling Processor                               │   │  │
│  │  │     - Keep all error traces                               │   │  │
│  │  │     - Sample successful traces                            │   │  │
│  │  └──────────────────────────────────────────────────────────┘   │  │
│  │                                                                    │  │
│  └────────────────────────────┬───────────────────────────────────────┘  │
│                               │                                           │
│  ┌────────────────────────────▼─────────────────────────────────────┐  │
│  │                    Exporter Layer                                 │  │
│  │                                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │  │
│  │  │ Dynatrace    │  │ Jaeger       │  │ Prometheus   │          │  │
│  │  │ OTLP HTTP    │  │ gRPC         │  │ Remote Write │          │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │  │
│  │         │                  │                  │                   │  │
│  └─────────┼──────────────────┼──────────────────┼────────────────────┘  │
│            │                  │                  │                      │
└────────────┼──────────────────┼──────────────────┼──────────────────────┘
             │                  │                  │
┌────────────▼──────────────────▼──────────────────▼──────────────────────┐
│                CAMADA 4: OBSERVABILITY BACKENDS                           │
│                                                                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │
│  │   Dynatrace     │  │     Jaeger      │  │   Prometheus    │        │
│  │                 │  │                 │  │                 │        │
│  │  - Distributed  │  │  - Trace UI     │  │  - Metrics      │        │
│  │    Tracing      │  │  - Root cause   │  │  - Dashboards   │        │
│  │  - Service Map  │  │    analysis     │  │  - Alerting     │        │
│  │  - Dashboards   │  │  - Performance  │  │  - Grafana      │        │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘        │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

## Componentes Detalhados

### 1. Camada de Instrumentação (z/OS)

#### 1.1 COBOL Bridge (via JNI)

```cobol
*> OTEL-BRIDGE.cbl
*> Bridge OpenTelemetry para programas COBOL

IDENTIFICATION DIVISION.
PROGRAM-ID. OTEL-BRIDGE.

ENVIRONMENT DIVISION.
CONFIGURATION SECTION.

DATA DIVISION.
WORKING-STORAGE SECTION.
01  JAVA-CLASS-NAME         PIC X(128) VALUE 
    'com.mainframe.otel.CobolBridge'.
01  JAVA-METHOD-NAME        PIC X(64).
01  JAVA-SIGNATURE          PIC X(128).
01  JNI-ENV-PTR            POINTER.
01  JNI-CLASS-PTR          POINTER.
01  JNI-METHOD-PTR         POINTER.

PROCEDURE DIVISION.

*> Inicializar OpenTelemetry
INITIALIZE-OTEL.
    MOVE 'initialize' TO JAVA-METHOD-NAME
    MOVE '(Ljava/lang/String;)V' TO JAVA-SIGNATURE
    
    CALL 'JNIENV' USING JNI-ENV-PTR
    CALL 'JCLASS' USING JNI-ENV-PTR 
                       JAVA-CLASS-NAME 
                       JNI-CLASS-PTR
    CALL 'JMETHOD' USING JNI-ENV-PTR 
                        JNI-CLASS-PTR
                        JAVA-METHOD-NAME 
                        JAVA-SIGNATURE 
                        JNI-METHOD-PTR
    GOBACK.
```

#### 1.2 Java SDK Integration

```java
package com.mainframe.otel;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.autoconfigure.AutoConfiguredOpenTelemetrySdk;

/**
 * Bridge para integração com programas COBOL
 */
public class CobolBridge {
    
    private static OpenTelemetrySdk openTelemetry;
    private static Tracer tracer;
    private static Map<String, Span> activeSpans = new ConcurrentHashMap<>();
    
    /**
     * Inicializa OpenTelemetry SDK
     * Chamado via JNI por programas COBOL
     */
    public static void initialize(String serviceName) {
        // Auto-configuração via variáveis de ambiente
        openTelemetry = AutoConfiguredOpenTelemetrySdk.initialize()
            .getOpenTelemetrySdk();
        
        tracer = openTelemetry.getTracer(serviceName, "1.0.0");
        
        // Registrar shutdown hook
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            openTelemetry.close();
        }));
    }
    
    /**
     * Cria um novo span
     * @param spanId ID único do span (gerado pelo COBOL)
     * @param operationName Nome da operação
     * @return status (0=sucesso, -1=erro)
     */
    public static int createSpan(String spanId, String operationName) {
        try {
            Span span = tracer.spanBuilder(operationName)
                .setSpanKind(SpanKind.INTERNAL)
                .startSpan();
            
            activeSpans.put(spanId, span);
            return 0;
        } catch (Exception e) {
            System.err.println("Error creating span: " + e.getMessage());
            return -1;
        }
    }
    
    /**
     * Adiciona atributo ao span
     */
    public static int addAttribute(String spanId, String key, String value) {
        Span span = activeSpans.get(spanId);
        if (span != null) {
            span.setAttribute(key, value);
            return 0;
        }
        return -1;
    }
    
    /**
     * Finaliza o span
     */
    public static int endSpan(String spanId) {
        Span span = activeSpans.remove(spanId);
        if (span != null) {
            span.end();
            return 0;
        }
        return -1;
    }
}
```

### 2. Camada de Exportação

#### 2.1 Exportador OTLP com Retry

```java
package com.mainframe.otel.export;

import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.trace.export.SpanExporter;
import java.time.Duration;

public class ResilientOtlpExporter {
    
    public static SpanExporter create(String endpoint) {
        OtlpGrpcSpanExporter baseExporter = OtlpGrpcSpanExporter.builder()
            .setEndpoint(endpoint)
            .setTimeout(Duration.ofSeconds(30))
            .setCompression("gzip")
            .build();
        
        // Wrapper com retry e circuit breaker
        return new RetryingSpanExporter(
            baseExporter,
            RetryConfig.builder()
                .maxAttempts(3)
                .initialDelay(Duration.ofSeconds(1))
                .maxDelay(Duration.ofSeconds(30))
                .backoffMultiplier(2.0)
                .build()
        );
    }
}

class RetryingSpanExporter implements SpanExporter {
    
    private final SpanExporter delegate;
    private final RetryConfig config;
    private final CircuitBreaker circuitBreaker;
    
    @Override
    public CompletableResultCode export(Collection<SpanData> spans) {
        return circuitBreaker.executeWithFallback(
            () -> exportWithRetry(spans),
            () -> fallbackExport(spans)
        );
    }
    
    private CompletableResultCode exportWithRetry(Collection<SpanData> spans) {
        int attempt = 0;
        Duration delay = config.initialDelay;
        
        while (attempt < config.maxAttempts) {
            try {
                CompletableResultCode result = delegate.export(spans);
                if (result.isSuccess()) {
                    circuitBreaker.recordSuccess();
                    return result;
                }
            } catch (Exception e) {
                attempt++;
                if (attempt >= config.maxAttempts) {
                    circuitBreaker.recordFailure();
                    throw e;
                }
                
                // Exponential backoff
                Thread.sleep(delay.toMillis());
                delay = Duration.ofMillis(
                    (long) (delay.toMillis() * config.backoffMultiplier)
                ).coerceAtMost(config.maxDelay);
            }
        }
        
        return CompletableResultCode.ofFailure();
    }
    
    private CompletableResultCode fallbackExport(Collection<SpanData> spans) {
        // Fallback: salvar em disco para processamento posterior
        DiskQueue.getInstance().enqueue(spans);
        return CompletableResultCode.ofSuccess();
    }
}
```

#### 2.2 Disk Queue para Resiliência

```java
package com.mainframe.otel.export;

import java.nio.file.*;
import java.io.*;

/**
 * Fila em disco para casos onde o coletor está indisponível
 */
public class DiskQueue {
    
    private static final String QUEUE_DIR = "/u/otel/queue";
    private static final int MAX_QUEUE_SIZE_MB = 100;
    
    private static DiskQueue instance;
    private final Path queuePath;
    
    private DiskQueue() {
        this.queuePath = Paths.get(QUEUE_DIR);
        try {
            Files.createDirectories(queuePath);
        } catch (IOException e) {
            throw new RuntimeException("Failed to create queue directory", e);
        }
    }
    
    public static synchronized DiskQueue getInstance() {
        if (instance == null) {
            instance = new DiskQueue();
        }
        return instance;
    }
    
    public void enqueue(Collection<SpanData> spans) {
        String filename = String.format("spans_%d.bin", 
            System.currentTimeMillis());
        Path file = queuePath.resolve(filename);
        
        try (DataOutputStream out = new DataOutputStream(
                new GZIPOutputStream(
                    new BufferedOutputStream(
                        Files.newOutputStream(file))))) {
            
            // Serializar spans para formato OTLP protobuf
            byte[] data = serializeToOtlp(spans);
            out.write(data);
            
        } catch (IOException e) {
            System.err.println("Failed to enqueue spans: " + e.getMessage());
        }
        
        // Verificar tamanho da fila e limpar se necessário
        cleanupIfNeeded();
    }
    
    public List<Collection<SpanData>> dequeueAll() {
        List<Collection<SpanData>> result = new ArrayList<>();
        
        try (DirectoryStream<Path> stream = 
                Files.newDirectoryStream(queuePath, "spans_*.bin")) {
            
            for (Path file : stream) {
                try (DataInputStream in = new DataInputStream(
                        new GZIPInputStream(
                            new BufferedInputStream(
                                Files.newInputStream(file))))) {
                    
                    byte[] data = in.readAllBytes();
                    Collection<SpanData> spans = deserializeFromOtlp(data);
                    result.add(spans);
                    
                    // Remover arquivo após leitura
                    Files.delete(file);
                    
                } catch (IOException e) {
                    System.err.println("Failed to dequeue file: " + 
                        file + " - " + e.getMessage());
                }
            }
            
        } catch (IOException e) {
            System.err.println("Failed to list queue directory: " + 
                e.getMessage());
        }
        
        return result;
    }
    
    private void cleanupIfNeeded() {
        try {
            long totalSize = Files.walk(queuePath)
                .filter(Files::isRegularFile)
                .mapToLong(p -> {
                    try {
                        return Files.size(p);
                    } catch (IOException e) {
                        return 0;
                    }
                })
                .sum();
            
            if (totalSize > MAX_QUEUE_SIZE_MB * 1024 * 1024) {
                // Remover arquivos mais antigos
                Files.walk(queuePath)
                    .filter(Files::isRegularFile)
                    .sorted(Comparator.comparingLong(p -> {
                        try {
                            return Files.getLastModifiedTime(p).toMillis();
                        } catch (IOException e) {
                            return 0;
                        }
                    }))
                    .limit(10)
                    .forEach(p -> {
                        try {
                            Files.delete(p);
                        } catch (IOException e) {
                            // Ignore
                        }
                    });
            }
        } catch (IOException e) {
            System.err.println("Failed to cleanup queue: " + e.getMessage());
        }
    }
}
```

### 3. Collector Configuration

#### 3.1 High Availability Setup

```yaml
# Configuração HA com múltiplos collectors

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 4
        max_concurrent_streams: 100
        
        # Configurações de rate limiting
        read_buffer_size: 524288
        write_buffer_size: 524288
        
        # Keep-alive para conexões longas do mainframe
        keepalive:
          server_parameters:
            max_connection_idle: 30s
            max_connection_age: 1h
            max_connection_age_grace: 5s
            time: 30s
            timeout: 10s
          enforcement_policy:
            min_time: 10s
            permit_without_stream: true

processors:
  # Batch otimizado para mainframe
  batch/mainframe:
    timeout: 10s
    send_batch_size: 1000
    send_batch_max_size: 2000
    
  # Load balancing entre múltiplos coletores
  loadbalancing:
    protocol:
      otlp:
        timeout: 1s
    resolver:
      static:
        hostnames:
          - otel-collector-1:4317
          - otel-collector-2:4317
          - otel-collector-3:4317
          
  # Tail sampling inteligente
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    expected_new_traces_per_sec: 1000
    policies:
      # Sempre manter erros
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      # Manter todas do mainframe durante debugging
      - name: mainframe-debug
        type: string_attribute
        string_attribute:
          key: source.platform
          values: [mainframe]
          enabled_regex_matching: false
      # Sample sucessos em 10%
      - name: successful-sampling
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

exporters:
  # Load balancing nos backends
  loadbalancing/dynatrace:
    protocol:
      otlphttp:
        endpoint: https://tenant.live.dynatrace.com/api/v2/otlp
        headers:
          Authorization: "Api-Token ${DYNATRACE_API_TOKEN}"
    resolver:
      dns:
        hostname: tenant.live.dynatrace.com
        port: 443

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch/mainframe, tail_sampling, loadbalancing]
      exporters: [loadbalancing/dynatrace]
```

## Fluxo de Dados Detalhado

### 1. Geração de Telemetria

```
JES Job Execution
        │
        ├─> Step 1 Execution
        │   ├─> Create Span (job.step.start)
        │   ├─> Execute Program
        │   │   └─> Add attributes (cpu, memory, etc)
        │   └─> End Span (job.step.complete)
        │
        ├─> Step 2 Execution
        │   └─> [similar to Step 1]
        │
        └─> Job Completion
            └─> End Root Span (job.complete)
```

### 2. Processamento Local

```
Span Generation
        │
        ▼
Batch Processor (collect 100 spans or 10s)
        │
        ▼
Resource Processor (add mainframe metadata)
        │
        ▼
Memory Buffer (ring buffer, 2048 spans)
        │
        ▼
Compression (gzip, ~70% reduction)
        │
        ▼
Export Attempt
```

### 3. Exportação com Fallback

```
Primary Path: OTLP/gRPC
        │
        ├─ Success ──> Collector
        │
        └─ Failure
            │
            ▼
        Retry (3x with backoff)
            │
            ├─ Success ──> Collector
            │
            └─ Failure
                │
                ▼
            Circuit Breaker Open
                │
                ▼
            Disk Queue (/u/otel/queue)
                │
                └─> Background process retries later
```

## Considerações de Segurança

### 1. Autenticação e Autorização

```yaml
# Configuração de segurança no collector

extensions:
  # Autenticação via Bearer Token
  bearertokenauth:
    scheme: "Bearer"
    token: "${MAINFRAME_AUTH_TOKEN}"
    
  # Ou via API Key
  headers_setter:
    headers:
      - key: X-API-Key
        from_context: api_key

receivers:
  otlp:
    protocols:
      grpc:
        auth:
          authenticator: bearertokenauth
        tls:
          cert_file: /etc/otel/certs/server.crt
          key_file: /etc/otel/certs/server.key
          client_ca_file: /etc/otel/certs/ca.crt
          min_version: "1.3"
```

### 2. Redação de Dados Sensíveis

```java
public class SensitiveDataRedactor implements SpanProcessor {
    
    private static final List<String> SENSITIVE_KEYS = Arrays.asList(
        "credit_card", "password", "ssn", "cpf", "account_number"
    );
    
    @Override
    public void onStart(Context parentContext, ReadWriteSpan span) {
        // Redact sensitive attributes
        span.getAttributes().forEach((key, value) -> {
            if (isSensitive(key.getKey())) {
                span.setAttribute(key, "***REDACTED***");
            }
        });
    }
    
    private boolean isSensitive(String key) {
        return SENSITIVE_KEYS.stream()
            .anyMatch(sensitive -> key.toLowerCase().contains(sensitive));
    }
}
```

## Métricas de Performance

### Latências Esperadas

| Componente | Latência Típica | Latência P95 | Latência P99 |
|------------|----------------|--------------|--------------|
| Span Creation | < 1ms | 2ms | 5ms |
| Batch Processing | 10s (config) | 11s | 15s |
| Network Export (mainframe→collector) | 50-100ms | 200ms | 500ms |
| Collector Processing | 10-50ms | 100ms | 200ms |
| Backend Export (collector→Dynatrace) | 100-200ms | 500ms | 1s |
| **Total E2E** | **~10s** | **~12s** | **~17s** |

### Throughput

- **Mainframe**: 10,000 spans/segundo por instância
- **Collector**: 100,000 spans/segundo por instância
- **Network**: Limitado a banda disponível (~1Gbps típico)

### Recursos

| Componente | CPU | Memória | Disco | Rede |
|------------|-----|---------|-------|------|
| Java Agent (z/OS) | < 5% | 256MB | 100MB (queue) | 1-10 Mbps |
| Collector (Linux) | 2-4 cores | 2-4GB | 10GB (buffer) | 100 Mbps |

## Próximos Passos

1. [Implementação Rápida](./MAINFRAME_OTEL_QUICKSTART.md)
2. [Guia Completo](./MAINFRAME_JES_OPENTELEMETRY_MONITORING.md)
3. Implementação de Dashboards
4. Configuração de Alertas
5. Integração com CI/CD

---

**Versão**: 1.0  
**Última Atualização**: Novembro 2024
