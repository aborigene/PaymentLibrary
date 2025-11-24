# Guia Rápido: Monitoramento de Jobs JES com OpenTelemetry

## Início Rápido em 15 Minutos

Este guia fornece um caminho rápido para começar a monitorar jobs JES no mainframe usando OpenTelemetry.

## Pré-requisitos

- [ ] z/OS com Java 8 ou superior instalado
- [ ] Acesso SSH ao mainframe
- [ ] Servidor Linux/Windows para hospedar o OpenTelemetry Collector
- [ ] Conectividade de rede entre mainframe e coletor

## Passo 1: Configurar o OpenTelemetry Collector (5 minutos)

### 1.1 Instalar o Collector

```bash
# Download do OpenTelemetry Collector
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.91.0/otelcol-contrib_0.91.0_linux_amd64.tar.gz

# Extrair
tar -xzf otelcol-contrib_0.91.0_linux_amd64.tar.gz

# Mover para diretório apropriado
sudo mv otelcol-contrib /usr/local/bin/
```

### 1.2 Criar Configuração Básica

Criar arquivo `otel-config.yaml`:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
    send_batch_size: 100
  
  resource:
    attributes:
      - key: source.platform
        value: mainframe
        action: insert

exporters:
  logging:
    loglevel: debug
  
  # Dynatrace (opcional)
  otlphttp/dynatrace:
    endpoint: https://YOUR_TENANT.live.dynatrace.com/api/v2/otlp
    headers:
      Authorization: "Api-Token YOUR_API_TOKEN"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [logging]  # Adicione dynatrace depois
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [logging]
```

### 1.3 Iniciar o Collector

```bash
# Executar em modo debug
otelcol-contrib --config otel-config.yaml

# Verificar se está rodando
curl http://localhost:13133/
```

## Passo 2: Configurar Exportador no Mainframe (5 minutos)

### 2.1 Criar Diretório para OpenTelemetry

```bash
# SSH no mainframe
ssh user@mainframe.company.com

# Criar estrutura de diretórios
mkdir -p /u/otel/lib
mkdir -p /u/otel/config
mkdir -p /u/otel/logs
```

### 2.2 Fazer Upload dos JARs OpenTelemetry

Baixe e faça upload dos seguintes JARs:

```bash
# No seu computador local
wget https://github.com/open-telemetry/opentelemetry-java/releases/download/v1.32.0/opentelemetry-javaagent.jar

# Upload para o mainframe via SCP ou FTP
scp opentelemetry-javaagent.jar user@mainframe:/u/otel/lib/
```

### 2.3 Criar Configuração do SDK

Criar arquivo `/u/otel/config/otel-sdk.properties`:

```properties
otel.service.name=mainframe-jes-monitor
otel.exporter.otlp.endpoint=http://otel-collector-host:4317
otel.exporter.otlp.protocol=grpc
otel.traces.exporter=otlp
otel.metrics.exporter=otlp
otel.logs.exporter=otlp
otel.resource.attributes=platform=zos,service.namespace=mainframe
```

## Passo 3: Instrumentar um Job Simples (5 minutos)

### 3.1 Criar Job de Teste com Monitoramento

Criar arquivo Java `SimpleJobMonitor.java`:

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;

public class SimpleJobMonitor {
    
    private static final Tracer tracer = 
        GlobalOpenTelemetry.getTracer("simple-job-monitor");
    
    public static void main(String[] args) {
        String jobName = System.getenv("JOBNAME");
        
        // Criar span para o job
        Span jobSpan = tracer.spanBuilder("jes.job.test")
            .setAttribute("job.name", jobName != null ? jobName : "TESTJOB")
            .setAttribute("job.type", "TEST")
            .startSpan();
            
        try (Scope scope = jobSpan.makeCurrent()) {
            System.out.println("Iniciando monitoramento do job: " + jobName);
            
            // Simular trabalho
            processStep("STEP1");
            processStep("STEP2");
            processStep("STEP3");
            
            jobSpan.setStatus(io.opentelemetry.api.trace.StatusCode.OK);
            System.out.println("Job concluído com sucesso!");
            
        } catch (Exception e) {
            jobSpan.recordException(e);
            jobSpan.setStatus(io.opentelemetry.api.trace.StatusCode.ERROR);
            e.printStackTrace();
        } finally {
            jobSpan.end();
            
            // Aguardar para garantir que spans sejam exportados
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }
    }
    
    private static void processStep(String stepName) throws Exception {
        Span stepSpan = tracer.spanBuilder("jes.job.step")
            .setAttribute("step.name", stepName)
            .startSpan();
            
        try (Scope scope = stepSpan.makeCurrent()) {
            System.out.println("  Executando step: " + stepName);
            
            // Simular processamento
            Thread.sleep(500);
            
            stepSpan.setAttribute("step.status", "COMPLETED");
            stepSpan.setStatus(io.opentelemetry.api.trace.StatusCode.OK);
            
        } catch (Exception e) {
            stepSpan.recordException(e);
            stepSpan.setStatus(io.opentelemetry.api.trace.StatusCode.ERROR);
            throw e;
        } finally {
            stepSpan.end();
        }
    }
}
```

### 3.2 Compilar e Executar

```bash
# Compilar
javac -cp "/u/otel/lib/*" SimpleJobMonitor.java

# Executar com OpenTelemetry Java Agent
java -javaagent:/u/otel/lib/opentelemetry-javaagent.jar \
     -Dotel.javaagent.configuration-file=/u/otel/config/otel-sdk.properties \
     -cp ".:​/u/otel/lib/*" \
     SimpleJobMonitor
```

### 3.3 Criar JCL para Executar o Job

Criar membro `TESTJES` em uma biblioteca PDS:

```jcl
//TESTJES  JOB (ACCT),'OTEL TEST JOB',CLASS=A,MSGCLASS=H,
//         NOTIFY=&SYSUID
//*
//**************************************************************
//* JOB DE TESTE COM MONITORAMENTO OPENTELEMETRY
//**************************************************************
//*
//STEP1    EXEC PGM=BPXBATCH
//STDOUT   DD SYSOUT=*
//STDERR   DD SYSOUT=*
//STDPARM  DD *
SH cd /u/otel && \
   java -javaagent:lib/opentelemetry-javaagent.jar \
        -Dotel.javaagent.configuration-file=config/otel-sdk.properties \
        -cp ".:lib/*" \
        SimpleJobMonitor
/*
//
```

## Validação

### 1. Verificar Logs do Collector

No servidor do collector, verificar os logs:

```bash
# Você deve ver algo como:
2024-11-24T10:15:30.123Z INFO Traces [...]
    -> Name: jes.job.test
    -> SpanKind: Internal
    -> Attributes:
        - job.name: TESTJOB
        - job.type: TEST
```

### 2. Verificar no Dynatrace (se configurado)

1. Acesse Dynatrace UI
2. Navegue para **Distributed Traces**
3. Filtrar por `service.name = mainframe-jes-monitor`
4. Você deve ver o trace do job com todos os steps

### 3. Verificar com Jaeger (alternativa)

Se estiver usando Jaeger:

```bash
# Acessar UI do Jaeger
http://jaeger-host:16686

# Procurar por:
- Service: mainframe-jes-monitor
- Operation: jes.job.test
```

## Próximos Passos

Agora que você tem um setup básico funcionando:

1. **Expandir para Jobs Reais**: Instrumentar jobs de produção
2. **Adicionar Métricas**: Coletar métricas de performance
3. **Configurar Dashboards**: Criar visualizações no Grafana/Dynatrace
4. **Implementar Alertas**: Configurar alertas para falhas
5. **Correlação Distribuída**: Integrar com aplicações fora do mainframe

## Troubleshooting Rápido

### Problema: Collector não recebe dados

```bash
# 1. Verificar conectividade
telnet otel-collector-host 4317

# 2. Verificar firewall no mainframe
netstat -an | grep 4317

# 3. Verificar logs do Java Agent
java -Dotel.javaagent.debug=true ...
```

### Problema: Erro de certificado TLS

```bash
# Usar modo insecure temporariamente para teste
otel.exporter.otlp.endpoint=http://otel-collector-host:4317
# (não use em produção!)
```

### Problema: Job não envia spans

```bash
# Verificar se o Java Agent está carregado
# Deve aparecer nas mensagens de startup:
# [otel.javaagent] OpenTelemetry Javaagent enabled

# Adicionar debug:
-Dotel.javaagent.debug=true
```

## Checklist de Sucesso

- [ ] OpenTelemetry Collector rodando e acessível
- [ ] Java Agent configurado no mainframe
- [ ] Job de teste executado com sucesso
- [ ] Spans visíveis nos logs do collector
- [ ] (Opcional) Traces visíveis no backend (Dynatrace/Jaeger)
- [ ] Conectividade de rede confirmada
- [ ] Sem erros nos logs do mainframe

## Recursos

- [Documentação Completa](./MAINFRAME_JES_OPENTELEMETRY_MONITORING.md)
- [OpenTelemetry Java](https://opentelemetry.io/docs/instrumentation/java/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Dynatrace OpenTelemetry](https://www.dynatrace.com/support/help/extend-dynatrace/opentelemetry)

## Suporte

Para problemas ou dúvidas:
- Revise a documentação completa
- Verifique os logs em `/u/otel/logs`
- Consulte a comunidade OpenTelemetry
- Entre em contato com o time de plataforma

---

**Tempo Total**: ~15 minutos  
**Dificuldade**: Iniciante  
**Última Atualização**: Novembro 2024
