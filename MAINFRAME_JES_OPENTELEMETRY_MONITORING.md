# Monitoramento de Jobs JES no Mainframe com OpenTelemetry

## Visão Geral

Este documento descreve como monitorar jobs de mainframe rodando com JES (Job Entry Subsystem) utilizando OpenTelemetry (OTel) e como os dados de telemetria são exportados do mainframe até chegar a um coletor OpenTelemetry.

## Índice

1. [Introdução ao JES e OpenTelemetry](#introdução)
2. [Arquitetura de Monitoramento](#arquitetura)
3. [Implementação no Mainframe](#implementação)
4. [Exportação de Dados](#exportação-de-dados)
5. [Configuração do Coletor](#configuração-do-coletor)
6. [Exemplos Práticos](#exemplos-práticos)
7. [Melhores Práticas](#melhores-práticas)

## Introdução

### O que é JES?

O **JES (Job Entry Subsystem)** é um componente fundamental do z/OS que gerencia a entrada, execução e saída de jobs em ambientes mainframe. Existem duas versões principais:
- **JES2**: Mais tradicional, focado em processamento batch
- **JES3**: Oferece recursos avançados de gerenciamento e scheduling

### OpenTelemetry no Mainframe

OpenTelemetry é um framework de observabilidade que fornece APIs, bibliotecas e agentes para coletar traces, métricas e logs de aplicações. No contexto do mainframe, o OTel permite:
- Visibilidade end-to-end de jobs JES
- Correlação entre aplicações mainframe e distribuídas
- Análise de performance e troubleshooting
- Integração com plataformas modernas de observabilidade

## Arquitetura

### Arquitetura de Referência

```
┌─────────────────────────────────────────────────────────────┐
│                        Mainframe z/OS                        │
│                                                              │
│  ┌──────────────┐      ┌─────────────────────────────┐    │
│  │   JES2/JES3  │      │   OpenTelemetry SDK/Agent   │    │
│  │              │      │   (COBOL/Assembler/Java)    │    │
│  │  - Job Queue │──────▶                             │    │
│  │  - Job Exec  │      │   - Trace Generation        │    │
│  │  - Job Output│      │   - Metrics Collection      │    │
│  └──────────────┘      │   - Log Correlation         │    │
│                        └──────────────┬──────────────┘    │
│                                       │                     │
│                        ┌──────────────▼──────────────┐    │
│                        │   OTel Exporter (z/OS)     │    │
│                        │   - OTLP over TCP          │    │
│                        │   - HTTP/HTTPS             │    │
│                        │   - AT-TLS Encryption      │    │
│                        └──────────────┬──────────────┘    │
└────────────────────────────────────────┼──────────────────┘
                                         │
                                         │ OTLP Protocol
                                         │ (gRPC/HTTP)
                                         ▼
                        ┌────────────────────────────────┐
                        │   OpenTelemetry Collector      │
                        │   (Linux/Windows/Cloud)        │
                        │                                │
                        │   - Receiver (OTLP)           │
                        │   - Processor                  │
                        │   - Exporter                   │
                        └──────────────┬─────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
           ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
           │  Dynatrace  │   │ Prometheus  │   │   Jaeger    │
           │             │   │   Grafana   │   │  Splunk     │
           └─────────────┘   └─────────────┘   └─────────────┘
```

## Implementação

### 1. Estratégias de Instrumentação

#### Opção A: Instrumentação em COBOL

Para programas COBOL existentes, use a API OpenTelemetry para COBOL (via JNI):

```cobol
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PAYMENTJOB.
       
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-TRACE-CONTEXT    PIC X(128).
       01  WS-SPAN-ID          PIC X(16).
       01  WS-JOB-NAME         PIC X(8).
       01  WS-STEP-NAME        PIC X(8).
       
       PROCEDURE DIVISION.
       MAIN-PROCEDURE.
           MOVE JOBNAME TO WS-JOB-NAME
           
      *    Inicializar OpenTelemetry Tracer
           CALL 'OTELSTRT' USING WS-JOB-NAME WS-TRACE-CONTEXT
           
      *    Criar span para o job
           CALL 'OTELSPAN' USING 'JOB-EXECUTION' WS-SPAN-ID
           
      *    Adicionar atributos ao span
           CALL 'OTELATTR' USING WS-SPAN-ID 'job.name' WS-JOB-NAME
           CALL 'OTELATTR' USING WS-SPAN-ID 'job.type' 'PAYMENT'
           
      *    Executar lógica do job
           PERFORM PROCESS-PAYMENTS
           
      *    Finalizar span
           CALL 'OTELEND' USING WS-SPAN-ID
           
           STOP RUN.
           
       PROCESS-PAYMENTS.
      *    Criar span para cada etapa
           CALL 'OTELSPAN' USING 'PAYMENT-PROCESSING' WS-SPAN-ID
           
      *    Processar pagamentos
           PERFORM VALIDATE-PAYMENT
           PERFORM EXECUTE-PAYMENT
           
      *    Finalizar span
           CALL 'OTELEND' USING WS-SPAN-ID
           .
```

#### Opção B: Instrumentação em Java (z/OS)

Para aplicações Java rodando no z/OS:

```java
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;

public class JESJobMonitor {
    
    private static final Tracer tracer;
    
    static {
        // Configurar exportador OTLP
        OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
            .setEndpoint("http://otel-collector.company.com:4317")
            .build();
            
        SdkTracerProvider sdkTracerProvider = SdkTracerProvider.builder()
            .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
            .build();
            
        OpenTelemetry openTelemetry = OpenTelemetrySdk.builder()
            .setTracerProvider(sdkTracerProvider)
            .buildAndRegisterGlobal();
            
        tracer = openTelemetry.getTracer("jes-job-monitor", "1.0.0");
    }
    
    public void monitorJob(String jobName, String jobNumber) {
        // Criar span raiz para o job
        Span jobSpan = tracer.spanBuilder("jes.job.execution")
            .setAttribute("job.name", jobName)
            .setAttribute("job.number", jobNumber)
            .setAttribute("job.system", "JES2")
            .setAttribute("system.name", System.getProperty("system.name"))
            .startSpan();
            
        try (Scope scope = jobSpan.makeCurrent()) {
            // Monitorar cada step do job
            monitorJobSteps(jobName, jobNumber);
            
            // Coletar métricas de execução
            collectJobMetrics(jobName, jobNumber);
            
            jobSpan.setStatus(StatusCode.OK);
        } catch (Exception e) {
            jobSpan.recordException(e);
            jobSpan.setStatus(StatusCode.ERROR, e.getMessage());
            throw e;
        } finally {
            jobSpan.end();
        }
    }
    
    private void monitorJobSteps(String jobName, String jobNumber) {
        // Obter informações do JES via API
        JESAPIClient jesClient = new JESAPIClient();
        List<JobStep> steps = jesClient.getJobSteps(jobName, jobNumber);
        
        for (JobStep step : steps) {
            Span stepSpan = tracer.spanBuilder("jes.job.step")
                .setAttribute("step.name", step.getName())
                .setAttribute("step.program", step.getProgram())
                .setAttribute("step.condition.code", step.getConditionCode())
                .setAttribute("step.cpu.time", step.getCpuTime())
                .setAttribute("step.elapsed.time", step.getElapsedTime())
                .startSpan();
                
            try (Scope scope = stepSpan.makeCurrent()) {
                // Processar informações do step
                processStepDetails(step);
            } finally {
                stepSpan.end();
            }
        }
    }
    
    private void collectJobMetrics(String jobName, String jobNumber) {
        // Coletar métricas usando OpenTelemetry Metrics API
        Meter meter = GlobalOpenTelemetry.getMeter("jes-job-monitor");
        
        LongCounter jobCounter = meter
            .counterBuilder("jes.jobs.executed")
            .setDescription("Total number of JES jobs executed")
            .setUnit("jobs")
            .build();
            
        jobCounter.add(1, 
            Attributes.of(
                AttributeKey.stringKey("job.name"), jobName,
                AttributeKey.stringKey("job.type"), "BATCH"
            )
        );
        
        // Métricas de duração
        DoubleHistogram duration = meter
            .histogramBuilder("jes.job.duration")
            .setDescription("JES job execution duration")
            .setUnit("ms")
            .build();
            
        duration.record(getJobDuration(jobName, jobNumber),
            Attributes.of(
                AttributeKey.stringKey("job.name"), jobName
            )
        );
    }
}
```

#### Opção C: Agente SMF (System Management Facilities)

Implementar um leitor SMF que converte registros SMF em spans OpenTelemetry:

```java
import io.opentelemetry.api.trace.Span;
import com.ibm.jzos.ZFile;

public class SMFToOTelConverter {
    
    public void processSMFRecords() {
        // Ler registros SMF tipo 30 (job/step information)
        try {
            ZFile smfFile = new ZFile("//DD:SMFDATA", "rb,type=record");
            byte[] record = new byte[32768];
            
            while (smfFile.read(record) > 0) {
                if (isSMF30Record(record)) {
                    processJobRecord(record);
                }
            }
            
            smfFile.close();
        } catch (Exception e) {
            logger.error("Error processing SMF records", e);
        }
    }
    
    private void processJobRecord(byte[] smfRecord) {
        // Extrair informações do registro SMF 30
        String jobName = extractJobName(smfRecord);
        String jobNumber = extractJobNumber(smfRecord);
        long startTime = extractStartTime(smfRecord);
        long endTime = extractEndTime(smfRecord);
        int conditionCode = extractConditionCode(smfRecord);
        
        // Criar span com as informações do SMF
        Span span = tracer.spanBuilder("jes.job.completed")
            .setStartTimestamp(startTime, TimeUnit.MICROSECONDS)
            .setAttribute("job.name", jobName)
            .setAttribute("job.number", jobNumber)
            .setAttribute("job.condition.code", conditionCode)
            .setAttribute("job.cpu.time", extractCpuTime(smfRecord))
            .setAttribute("job.elapsed.time", endTime - startTime)
            .setAttribute("source", "SMF30")
            .startSpan();
            
        span.end(endTime, TimeUnit.MICROSECONDS);
    }
}
```

### 2. Configuração do SDK OpenTelemetry no z/OS

#### Arquivo de Configuração (otel-config.yaml)

```yaml
# OpenTelemetry Configuration for z/OS
service:
  name: mainframe-jes-monitor
  version: 1.0.0

# Exportador OTLP
exporters:
  otlp:
    endpoint: otel-collector.company.com:4317
    protocol: grpc
    compression: gzip
    timeout: 10s
    retry:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s
    
    # Configuração de TLS para z/OS AT-TLS
    tls:
      insecure: false
      cert_file: /etc/otel/certs/client.crt
      key_file: /etc/otel/certs/client.key
      ca_file: /etc/otel/certs/ca.crt

# Processadores
processors:
  batch:
    timeout: 10s
    send_batch_size: 100
    send_batch_max_size: 500
    
  resource:
    attributes:
      - key: platform
        value: zos
        action: insert
      - key: service.namespace
        value: mainframe
        action: insert
      - key: host.name
        value: ${SYSNAME}
        action: insert

# Recursos
resource:
  attributes:
    service.name: jes-job-monitor
    deployment.environment: production
    telemetry.sdk.language: java
    telemetry.sdk.name: opentelemetry
    host.arch: s390x

# Propagação de contexto
propagators:
  - tracecontext
  - baggage
  - b3
  - jaeger

# Limites
limits:
  attribute_value_length_limit: 4096
  attribute_count_limit: 128
  event_count_limit: 128
  link_count_limit: 128
```

## Exportação de Dados

### Estratégias de Exportação do Mainframe

#### 1. OTLP via TCP/IP (Recomendado)

```
Mainframe (z/OS) ──[OTLP/gRPC]──▶ OTel Collector (Linux)
                   Port 4317
```

**Configuração JCL para executar o exportador:**

```jcl
//OTELEXP JOB (ACCT),'OTEL EXPORTER',CLASS=A,MSGCLASS=H
//STEP1   EXEC PGM=BPXBATCH
//STDOUT  DD SYSOUT=*
//STDERR  DD SYSOUT=*
//STDPARM DD *
SH java -Xms256m -Xmx1024m \
   -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 \
   -Dotel.service.name=jes-monitor \
   -Dotel.traces.exporter=otlp \
   -Dotel.metrics.exporter=otlp \
   -jar /u/otel/otel-exporter.jar
/*
```

#### 2. OTLP via HTTP/HTTPS

Para ambientes com restrições de gRPC:

```java
OtlpHttpSpanExporter spanExporter = OtlpHttpSpanExporter.builder()
    .setEndpoint("https://otel-collector.company.com:4318/v1/traces")
    .addHeader("Authorization", "Bearer " + apiToken)
    .setCompression("gzip")
    .build();
```

#### 3. Exportação via MQ (Message Queue)

Para integração com infraestrutura IBM MQ existente:

```java
public class MQOTelExporter implements SpanExporter {
    
    private MQQueueManager queueManager;
    private MQQueue otelQueue;
    
    public void export(Collection<SpanData> spans) {
        try {
            // Conectar ao Queue Manager
            queueManager = new MQQueueManager("QM1");
            
            // Abrir fila de destino
            int openOptions = MQConstants.MQOO_OUTPUT;
            otelQueue = queueManager.accessQueue("OTEL.SPANS.QUEUE", 
                                                 openOptions);
            
            // Serializar e enviar spans
            for (SpanData span : spans) {
                byte[] spanBytes = serializeSpan(span);
                MQMessage message = new MQMessage();
                message.write(spanBytes);
                
                MQPutMessageOptions pmo = new MQPutMessageOptions();
                otelQueue.put(message, pmo);
            }
            
            otelQueue.close();
            queueManager.disconnect();
            
        } catch (MQException e) {
            logger.error("Error exporting to MQ", e);
        }
    }
    
    private byte[] serializeSpan(SpanData span) {
        // Serializar para formato OTLP Protobuf
        return OtlpProtoSpan.toProto(span).toByteArray();
    }
}
```

#### 4. Exportação via Dataset/USS File

Para ambientes com conectividade limitada:

```java
public class FileBasedExporter implements SpanExporter {
    
    private static final String EXPORT_PATH = "/u/otel/exports/";
    
    public void export(Collection<SpanData> spans) {
        String timestamp = LocalDateTime.now().format(
            DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")
        );
        String filename = EXPORT_PATH + "spans_" + timestamp + ".json";
        
        try (BufferedWriter writer = new BufferedWriter(
                new FileWriter(filename))) {
            
            for (SpanData span : spans) {
                String json = spanToJson(span);
                writer.write(json);
                writer.newLine();
            }
            
            // Transferir via FTP para o coletor
            transferToCollector(filename);
            
        } catch (IOException e) {
            logger.error("Error exporting to file", e);
        }
    }
    
    private void transferToCollector(String filename) {
        // Usar FTP ou SFTP para transferir para o coletor
        FTPClient ftp = new FTPClient();
        try {
            ftp.connect("otel-collector.company.com");
            ftp.login("oteluser", "password");
            ftp.setFileType(FTP.BINARY_FILE_TYPE);
            
            FileInputStream input = new FileInputStream(filename);
            ftp.storeFile("/imports/" + new File(filename).getName(), input);
            input.close();
            
            ftp.logout();
        } catch (IOException e) {
            logger.error("Error transferring file", e);
        }
    }
}
```

### Configuração de Rede no z/OS

#### AT-TLS (Application Transparent TLS)

Configurar AT-TLS para criptografar comunicação OTLP:

```
TTLSRule MainframeOTelExport
{
  LocalAddr All
  RemoteAddr 10.20.30.40        # Endereço do OTel Collector
  RemotePortRange 4317
  Direction Outbound
  Priority 100
  TTLSGroupActionRef OTelClientAction
  TTLSEnvironmentActionRef OTelClientEnv
}

TTLSGroupAction OTelClientAction
{
  TTLSEnabled On
  Trace 7
}

TTLSEnvironmentAction OTelClientEnv
{
  HandshakeRole Client
  TTLSKeyringParmsRef OTelKeyring
  TTLSCipherParmsRef OTelCipher
}

TTLSKeyringParams OTelKeyring
{
  Keyring OTEL/RING
}

TTLSCipherParams OTelCipher
{
  V3CipherSuites TLS_AES_256_GCM_SHA384
  V3CipherSuites TLS_AES_128_GCM_SHA256
}
```

## Configuração do Coletor

### OpenTelemetry Collector (Linux/Cloud)

```yaml
# otel-collector-config.yaml

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        # Configurações de segurança
        tls:
          cert_file: /etc/otel/certs/server.crt
          key_file: /etc/otel/certs/server.key
          client_ca_file: /etc/otel/certs/ca.crt
      http:
        endpoint: 0.0.0.0:4318
        
  # Receiver para arquivos exportados do mainframe
  filelog:
    include:
      - /imports/spans_*.json
    operators:
      - type: json_parser
        timestamp:
          parse_from: attributes.timestamp
          layout: '%Y-%m-%dT%H:%M:%S.%fZ'

processors:
  # Processador de batch para otimizar envio
  batch:
    timeout: 10s
    send_batch_size: 1000
    
  # Enriquecimento de recursos
  resource:
    attributes:
      - key: source.platform
        value: mainframe
        action: insert
      - key: source.system
        value: zos
        action: insert
        
  # Filtros e transformações
  filter:
    traces:
      span:
        # Filtrar spans de teste
        - 'attributes["job.name"] == "TESTJOB"'
        
  # Amostragem para reduzir volume
  probabilistic_sampler:
    sampling_percentage: 100  # 100% em produção, ajustar se necessário
    
  # Atributos específicos para mainframe
  attributes:
    actions:
      - key: mainframe.system
        action: upsert
        value: MVS001
      - key: telemetry.source
        action: upsert
        value: jes-monitor

exporters:
  # Dynatrace
  otlphttp/dynatrace:
    endpoint: https://{your-environment-id}.live.dynatrace.com/api/v2/otlp
    headers:
      Authorization: "Api-Token ${DYNATRACE_API_TOKEN}"
      
  # Jaeger
  jaeger:
    endpoint: jaeger-collector:14250
    tls:
      insecure: false
      
  # Prometheus
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
    
  # Elasticsearch para logs
  elasticsearch:
    endpoints:
      - http://elasticsearch:9200
    index: mainframe-traces
    
  # Debug/logging
  logging:
    loglevel: info
    sampling_initial: 5
    sampling_thereafter: 200

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
  zpages:
    endpoint: 0.0.0.0:55679

service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource, filter, attributes]
      exporters: [otlphttp/dynatrace, jaeger, logging]
      
    metrics:
      receivers: [otlp]
      processors: [batch, resource, attributes]
      exporters: [prometheusremotewrite, logging]
      
    logs:
      receivers: [otlp, filelog]
      processors: [batch, resource, attributes]
      exporters: [elasticsearch, logging]

  telemetry:
    logs:
      level: info
    metrics:
      level: detailed
      address: 0.0.0.0:8888
```

### Docker Compose para OTel Collector

```yaml
version: '3.8'

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otel-collector
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
      - ./certs:/etc/otel/certs
      - ./imports:/imports
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
      - "13133:13133" # Health check
      - "8888:8888"   # Metrics
      - "55679:55679" # ZPages
    environment:
      - DYNATRACE_API_TOKEN=${DYNATRACE_API_TOKEN}
    networks:
      - otel-network
    restart: unless-stopped
    
  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: jaeger
    ports:
      - "16686:16686"  # UI
      - "14250:14250"  # gRPC
    networks:
      - otel-network
      
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - otel-network
      
networks:
  otel-network:
    driver: bridge
    
volumes:
  prometheus-data:
```

## Exemplos Práticos

### Exemplo 1: Monitoramento de Job Batch de Pagamento

```java
public class PaymentJobMonitor {
    
    private final Tracer tracer;
    private final Meter meter;
    
    public PaymentJobMonitor() {
        this.tracer = GlobalOpenTelemetry.getTracer("payment-job-monitor");
        this.meter = GlobalOpenTelemetry.getMeter("payment-job-monitor");
    }
    
    public void monitorPaymentJob(String jobName, String jobNumber) {
        // Criar span raiz para o job completo
        Span jobSpan = tracer.spanBuilder("payment.job.execution")
            .setAttribute("job.name", jobName)
            .setAttribute("job.number", jobNumber)
            .setAttribute("job.type", "PAYMENT_BATCH")
            .setAttribute("business.process", "daily-settlement")
            .startSpan();
            
        try (Scope scope = jobSpan.makeCurrent()) {
            
            // Step 1: Validação de arquivos de entrada
            Span validationSpan = tracer.spanBuilder("payment.validation")
                .startSpan();
            try (Scope validationScope = validationSpan.makeCurrent()) {
                int recordCount = validateInputFiles();
                validationSpan.setAttribute("records.validated", recordCount);
                validationSpan.setStatus(StatusCode.OK);
            } catch (Exception e) {
                validationSpan.recordException(e);
                validationSpan.setStatus(StatusCode.ERROR);
                throw e;
            } finally {
                validationSpan.end();
            }
            
            // Step 2: Processamento de pagamentos
            Span processingSpan = tracer.spanBuilder("payment.processing")
                .startSpan();
            try (Scope processingScope = processingSpan.makeCurrent()) {
                PaymentResult result = processPayments();
                
                // Adicionar métricas
                processingSpan.setAttribute("payments.processed", 
                    result.getProcessedCount());
                processingSpan.setAttribute("payments.failed", 
                    result.getFailedCount());
                processingSpan.setAttribute("total.amount", 
                    result.getTotalAmount());
                    
                // Registrar métricas
                recordMetrics(result);
                
                processingSpan.setStatus(StatusCode.OK);
            } catch (Exception e) {
                processingSpan.recordException(e);
                processingSpan.setStatus(StatusCode.ERROR);
                throw e;
            } finally {
                processingSpan.end();
            }
            
            // Step 3: Geração de relatórios
            Span reportSpan = tracer.spanBuilder("payment.reporting")
                .startSpan();
            try (Scope reportScope = reportSpan.makeCurrent()) {
                generateReports();
                reportSpan.setStatus(StatusCode.OK);
            } catch (Exception e) {
                reportSpan.recordException(e);
                reportSpan.setStatus(StatusCode.ERROR);
                throw e;
            } finally {
                reportSpan.end();
            }
            
            jobSpan.setAttribute("job.status", "COMPLETED");
            jobSpan.setStatus(StatusCode.OK);
            
        } catch (Exception e) {
            jobSpan.setAttribute("job.status", "FAILED");
            jobSpan.recordException(e);
            jobSpan.setStatus(StatusCode.ERROR, e.getMessage());
            throw e;
        } finally {
            jobSpan.end();
        }
    }
    
    private void recordMetrics(PaymentResult result) {
        // Counter para pagamentos processados
        LongCounter paymentsCounter = meter
            .counterBuilder("payments.processed.total")
            .setDescription("Total number of payments processed")
            .build();
        paymentsCounter.add(result.getProcessedCount());
        
        // Histogram para valores de pagamento
        DoubleHistogram paymentAmount = meter
            .histogramBuilder("payment.amount")
            .setDescription("Payment amount distribution")
            .setUnit("BRL")
            .build();
        paymentAmount.record(result.getTotalAmount());
        
        // Gauge para taxa de sucesso
        meter.gaugeBuilder("payment.success.rate")
            .setDescription("Payment success rate")
            .buildWithCallback(measurement -> {
                double successRate = (double) result.getProcessedCount() / 
                    (result.getProcessedCount() + result.getFailedCount());
                measurement.record(successRate * 100);
            });
    }
}
```

### Exemplo 2: Correlação entre Mainframe e APIs Distribuídas

```java
public class DistributedPaymentFlow {
    
    private final Tracer tracer;
    
    public void processDistributedPayment(String paymentId) {
        // Iniciar no mainframe
        Span mainframeSpan = tracer.spanBuilder("mainframe.payment.init")
            .setAttribute("payment.id", paymentId)
            .setAttribute("source.system", "mainframe")
            .startSpan();
            
        try (Scope scope = mainframeSpan.makeCurrent()) {
            
            // Extrair contexto para propagar
            W3CTraceContextPropagator propagator = 
                W3CTraceContextPropagator.getInstance();
            Map<String, String> carrier = new HashMap<>();
            propagator.inject(Context.current(), carrier, 
                (c, key, value) -> c.put(key, value));
            
            // Chamar API externa com contexto
            callExternalAPI(paymentId, carrier);
            
            mainframeSpan.setStatus(StatusCode.OK);
            
        } catch (Exception e) {
            mainframeSpan.recordException(e);
            mainframeSpan.setStatus(StatusCode.ERROR);
            throw e;
        } finally {
            mainframeSpan.end();
        }
    }
    
    private void callExternalAPI(String paymentId, 
                                  Map<String, String> traceContext) {
        // Criar requisição HTTP com headers de trace context
        HttpClient client = HttpClient.newHttpClient();
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create("https://api.bank.com/payments/" + paymentId))
            .header("traceparent", traceContext.get("traceparent"))
            .header("tracestate", traceContext.get("tracestate"))
            .POST(HttpRequest.BodyPublishers.ofString("{}"))
            .build();
            
        // A API receberá o contexto e criará spans conectados
        client.sendAsync(request, HttpResponse.BodyHandlers.ofString())
            .thenApply(HttpResponse::body)
            .join();
    }
}
```

### Exemplo 3: Integração com CICS

```java
public class CICSTransactionMonitor {
    
    private final Tracer tracer;
    
    public void monitorCICSTransaction(String transactionId) {
        // Obter informações da transação CICS
        CICSContext cicsContext = getCICSContext();
        
        Span transactionSpan = tracer.spanBuilder("cics.transaction")
            .setAttribute("transaction.id", transactionId)
            .setAttribute("cics.region", cicsContext.getRegion())
            .setAttribute("cics.applid", cicsContext.getApplid())
            .setAttribute("terminal.id", cicsContext.getTerminalId())
            .setAttribute("user.id", cicsContext.getUserId())
            .startSpan();
            
        try (Scope scope = transactionSpan.makeCurrent()) {
            
            // Monitorar programas chamados
            monitorProgramCalls(cicsContext);
            
            // Monitorar acessos a arquivos
            monitorFileAccess(cicsContext);
            
            // Monitorar chamadas temporárias
            monitorTempStorageQueue(cicsContext);
            
            transactionSpan.setAttribute("transaction.status", 
                cicsContext.getCompletionCode());
            transactionSpan.setStatus(StatusCode.OK);
            
        } catch (Exception e) {
            transactionSpan.recordException(e);
            transactionSpan.setStatus(StatusCode.ERROR);
            throw e;
        } finally {
            transactionSpan.end();
        }
    }
    
    private void monitorProgramCalls(CICSContext context) {
        List<ProgramCall> programs = context.getProgramCalls();
        
        for (ProgramCall program : programs) {
            Span programSpan = tracer.spanBuilder("cics.program.link")
                .setAttribute("program.name", program.getName())
                .setAttribute("program.language", program.getLanguage())
                .setAttribute("response.code", program.getResponseCode())
                .setStartTimestamp(program.getStartTime(), TimeUnit.MICROSECONDS)
                .startSpan();
                
            programSpan.end(program.getEndTime(), TimeUnit.MICROSECONDS);
        }
    }
}
```

## Melhores Práticas

### 1. Nomenclatura de Spans e Atributos

```java
// Nomenclatura consistente para spans
public class SpanNamingConventions {
    
    // Padrão: <sistema>.<componente>.<ação>
    public static final String JOB_EXECUTION = "jes.job.execution";
    public static final String JOB_STEP = "jes.job.step";
    public static final String CICS_TRANSACTION = "cics.transaction";
    public static final String DB2_QUERY = "db2.query";
    public static final String MQ_SEND = "mq.message.send";
    
    // Atributos semânticos padrão
    public static final AttributeKey<String> JOB_NAME = 
        AttributeKey.stringKey("job.name");
    public static final AttributeKey<String> JOB_NUMBER = 
        AttributeKey.stringKey("job.number");
    public static final AttributeKey<String> STEP_NAME = 
        AttributeKey.stringKey("step.name");
    public static final AttributeKey<Integer> CONDITION_CODE = 
        AttributeKey.longKey("job.condition.code");
}
```

### 2. Gerenciamento de Performance

```java
public class PerformanceOptimization {
    
    // Usar BatchSpanProcessor para otimizar envio
    public static SdkTracerProvider createOptimizedProvider() {
        return SdkTracerProvider.builder()
            .addSpanProcessor(
                BatchSpanProcessor.builder(createExporter())
                    .setScheduleDelay(Duration.ofSeconds(5))
                    .setMaxQueueSize(2048)
                    .setMaxExportBatchSize(512)
                    .setExporterTimeout(Duration.ofSeconds(30))
                    .build()
            )
            .setSampler(Sampler.parentBased(
                Sampler.traceIdRatioBased(1.0) // 100% sampling
            ))
            .build();
    }
    
    // Implementar circuit breaker para resiliência
    public static SpanExporter createResilientExporter() {
        SpanExporter baseExporter = OtlpGrpcSpanExporter.builder()
            .setEndpoint("http://otel-collector:4317")
            .setTimeout(Duration.ofSeconds(10))
            .build();
            
        return new CircuitBreakerSpanExporter(baseExporter, 
            CircuitBreakerConfig.builder()
                .failureThreshold(5)
                .successThreshold(2)
                .timeout(Duration.ofSeconds(60))
                .build()
        );
    }
}
```

### 3. Segurança e Compliance

```java
public class SecurityBestPractices {
    
    // Redação de dados sensíveis
    public static Span createSecureSpan(Tracer tracer, String operation) {
        Span span = tracer.spanBuilder(operation).startSpan();
        
        // Adicionar processor para redação
        span = new RedactingSpan(span, Arrays.asList(
            "credit_card", "ssn", "password", "cpf"
        ));
        
        return span;
    }
    
    // Validar certificados TLS
    public static OtlpGrpcSpanExporter createSecureExporter() {
        return OtlpGrpcSpanExporter.builder()
            .setEndpoint("https://otel-collector:4317")
            .setTrustedCertificates(loadTrustedCerts())
            .setClientTls(loadClientCerts(), loadClientKey())
            .build();
    }
    
    // Implementar rate limiting
    public static SpanExporter createRateLimitedExporter(
            SpanExporter delegate, int maxSpansPerSecond) {
        return new RateLimitingSpanExporter(delegate, 
            RateLimiter.create(maxSpansPerSecond));
    }
}
```

### 4. Monitoramento e Alertas

```yaml
# Prometheus alerts para monitoramento do pipeline

groups:
  - name: mainframe-otel-alerts
    interval: 30s
    rules:
      - alert: HighJobFailureRate
        expr: |
          rate(jes_jobs_failed_total[5m]) / 
          rate(jes_jobs_executed_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Alta taxa de falha em jobs JES"
          description: "Taxa de falha: {{ $value | humanizePercentage }}"
          
      - alert: OTelCollectorDown
        expr: up{job="otel-collector"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "OpenTelemetry Collector está down"
          
      - alert: HighSpanDropRate
        expr: |
          rate(otelcol_processor_dropped_spans[5m]) > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Alto número de spans descartados"
          
      - alert: ExportQueueFull
        expr: |
          otelcol_exporter_queue_size / 
          otelcol_exporter_queue_capacity > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Fila de exportação quase cheia"
```

### 5. Troubleshooting

#### Diagnóstico de Problemas Comuns

```bash
#!/bin/bash
# Script de diagnóstico para problemas de exportação

echo "=== OpenTelemetry Mainframe Diagnostics ==="

# 1. Verificar conectividade com o coletor
echo "\n1. Testing connectivity to OTel Collector..."
nc -zv otel-collector.company.com 4317

# 2. Verificar certificados TLS
echo "\n2. Checking TLS certificates..."
openssl s_client -connect otel-collector.company.com:4317 \
    -showcerts < /dev/null

# 3. Verificar logs do exportador no z/OS
echo "\n3. Checking z/OS exporter logs..."
ssh zos-system "tail -100 /u/otel/logs/exporter.log"

# 4. Verificar métricas do coletor
echo "\n4. Checking collector metrics..."
curl -s http://otel-collector:8888/metrics | grep -E "(receiver|exporter|processor)"

# 5. Testar envio de span de teste
echo "\n5. Sending test span..."
curl -X POST http://otel-collector:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test"}
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "00000000000000000000000000000001",
          "spanId": "0000000000000001",
          "name": "test-span",
          "kind": 1,
          "startTimeUnixNano": 1234567890000000000,
          "endTimeUnixNano": 1234567891000000000
        }]
      }]
    }]
  }'

echo "\n=== Diagnostics Complete ==="
```

## Recursos Adicionais

### Documentação de Referência

- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)
- [OTLP Protocol](https://opentelemetry.io/docs/specs/otlp/)
- [IBM z/OS OpenTelemetry Support](https://www.ibm.com/docs/en/zos)
- [JES2/JES3 Documentation](https://www.ibm.com/docs/en/zos/latest?topic=systems-jes2-jes3)

### Ferramentas e SDKs

- **OpenTelemetry Java SDK**: Para aplicações Java no z/OS
- **COBOL OpenTelemetry Bridge**: Via JNI para programas COBOL
- **IBM Z Open Automation Utilities**: Para integração com SMF
- **z/OS Connect**: Para APIs REST no mainframe

### Comunidade e Suporte

- [OpenTelemetry Community](https://opentelemetry.io/community/)
- [CNCF Slack - #otel-mainframe](https://cloud-native.slack.com)
- [IBM Z Community](https://community.ibm.com/community/user/ibmz-and-linuxone/home)

## Conclusão

O monitoramento de jobs JES com OpenTelemetry proporciona:

1. **Visibilidade End-to-End**: Traces distribuídos desde o mainframe até microsserviços
2. **Observabilidade Moderna**: Integração com ferramentas cloud-native
3. **Troubleshooting Eficiente**: Correlação de eventos entre sistemas
4. **Performance Analytics**: Métricas detalhadas de execução de jobs
5. **Compliance**: Auditoria e rastreamento de processamento

A implementação pode ser gradual, começando com jobs críticos e expandindo conforme necessário. O uso de padrões abertos como OpenTelemetry garante flexibilidade e evita vendor lock-in.

---

**Versão**: 1.0  
**Data**: Novembro 2024  
**Mantenedor**: PaymentLibrary Team
