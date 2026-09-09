# Presence — design

Data: 2026-09-08
Status: aprovado, pronto para plano de implementação

## Problema

O Microsoft Teams no macOS muda o status para "Ausente" (amarelo) quando o
sistema fica ocioso. Carlos quer que o status permaneça "Disponível" (verde)
enquanto ele estiver trabalhando, sem depender de mexer o mouse manualmente.

O Teams determina inatividade a partir do contador de inatividade do sistema
(`HIDIdleTime`, exposto pelo `IOHIDSystem`) e do bloqueio/protetor de tela.
Qualquer solução precisa manter esse contador baixo.

## Decisões tomadas

| Decisão | Escolha |
|---|---|
| Formato | App na barra de menus do macOS |
| Acionamento | Sempre ativo enquanto ligado, com desligamento automático opcional |
| Tela | Tela permanece acesa e desbloqueada enquanto ativo |
| Técnica | Híbrida com verificação: power assertion primeiro, input sintético como fallback |

Efeito colateral aceito: enquanto ativo, não há protetor de tela nem bloqueio
automático. O bloqueio manual continua funcionando normalmente.

## Verificação (concluída em 2026-09-08)

A premissa central — que `IOPMAssertionDeclareUserActivity` zera o
`HIDIdleTime` — **é falsa nesta máquina**.

Duas medições independentes, a segunda com o `idle-probe` do próprio projeto
(2026-09-09), numa janela de 858 segundos de ociosidade real — sem a
contaminação por input humano que invalidou a primeira tentativa durante o
design:

```
caffeinate -u   (2026-09-08):  idle ANTES =  63,7s | DEPOIS =  70,0s
idle-probe      (2026-09-09):  idle ANTES = 857,8s | DEPOIS = 858,8s
```

O contador não caiu em nenhuma das duas: seguiu subindo. Nenhuma flag do `caffeinate` resolve o
problema do Teams — as demais (`-d`, `-i`, `-s`, `-m`) apenas impedem o sono,
sem tocar no contador de inatividade.

**Consequências:**

1. `.synthetic` (tecla F15) é o modo normal de operação, não o fallback. A
   permissão de Acessibilidade é obrigatória.
2. A power assertion **continua sendo chamada em todo ciclo**. Ela não zera o
   contador, mas é o que mantém a tela acesa e destravada — e tela bloqueada
   deixa o Teams amarelo de qualquer forma. Os dois mecanismos são
   complementares, não alternativos.
3. O modo verificado é persistido (`Preferences.startMode`). Começar toda
   sessão em `.declared` gastaria ~90s redescobrindo o que já se sabe, com o
   status exposto nesse intervalo.

A arquitetura absorveu o resultado sem reescrita — era esse o objetivo de
tratar a verificação como parte do produto.

## Abordagem

O app declara atividade do usuário via IOKit
(`IOPMAssertionDeclareUserActivity` com `kIOPMUserActiveLocal`) e **verifica o
resultado** lendo o `HIDIdleTime`. A declaração não exige nenhuma permissão do
macOS e não injeta input, mas não há garantia documentada de que zere o
contador que o Teams observa.

Se a verificação mostrar que o contador continua subindo, o app escala para
input sintético (`CGEvent` de tecla F15 — inexistente em teclados Mac, nenhum
app reage a ela), que zera o contador com certeza mas exige permissão de
Acessibilidade.

O evento sintético é postado em `.cghidEventTap`, não em `.cgSessionEventTap`.
Eventos injetados no tap de sessão podem não alcançar o `IOHIDSystem` e,
portanto, não resetar o contador — o que anularia o fallback inteiro.

Ordem de privilégio: o caminho sem permissão é sempre tentado primeiro; a
permissão só é pedida quando comprovadamente necessária.

### Limite conhecido da verificação

Enquanto Carlos está de fato usando o Mac, o `HIDIdleTime` fica perto de zero
por causa do input humano, e a leitura não distingue "a assertion funcionou" de
"ele mexeu no mouse". A verificação só é informativa em janelas de ociosidade
real — que são exatamente as janelas em que o app precisa agir. O estado
exibido no menu diz "o contador está baixo", não "a assertion está funcionando";
a spec não promete mais do que isso.

## Plataforma e distribuição

- **macOS 14+**, arm64. `MenuBarExtra` e `SMAppService` exigem macOS 13+; 14 é o
  piso adotado para evitar APIs em transição.
- **App Sandbox desligado.** O acesso ao `IOHIDSystem` e o `CGEvent.post` não
  são possíveis sob sandbox. O app não é distribuído pela App Store.
- **Assinatura de código.** A permissão de Acessibilidade é vinculada pelo TCC
  ao bundle ID *e* à assinatura do binário. Com assinatura ad-hoc, cada rebuild
  gera um cdhash novo e o macOS revoga a permissão concedida — o app volta a
  pedir autorização a cada build. Duas saídas:
  1. Assinar com um certificado Developer ID estável, se Carlos tiver um.
  2. Aceitar reconceder a permissão a cada build durante o desenvolvimento, e
     assinar ad-hoc uma vez só na versão final instalada.

  O plano de implementação adota (2) por padrão e deixa (1) como configuração
  de uma linha no script de build. O bundle ID é fixo:
  `com.carlos.presence`.
- **Instalação.** O script de build produz `Presence.app`; um alvo `install`
  copia para `/Applications`. `SMAppService.mainApp` exige que o app esteja em
  uma localização estável — registrar o login item a partir da pasta de build
  produz um item quebrado assim que a pasta muda.

## Arquitetura

```
PresenceApp (SwiftUI, MenuBarExtra, LSUIElement)
   └── PresenceController      — máquina de estados, @MainActor
         ├── ActivityDeclarer  — IOPMAssertionDeclareUserActivity
         ├── IdleReader        — HIDIdleTime via IOHIDSystem (IOKit direto)
         ├── SyntheticInput    — CGEvent F15 em .cghidEventTap (fallback)
         ├── LockMonitor       — notificações de bloqueio/desbloqueio de tela
         └── Preferences       — UserDefaults
```

Build: Swift Package Manager + script de empacotamento do `.app`. Sem projeto
Xcode, para manter tudo em texto versionável. Toolchain Swift 6.3, com o
pacote em modo de linguagem 5: as APIs C do IOKit e os callbacks do
`DistributedNotificationCenter` geram atrito considerável sob strict
concurrency, sem benefício real para um app de um processo e uma thread.
`PresenceController` é `@MainActor` e a UI observa seu estado publicado.

### Componentes

**IdleReader** — lê `HIDIdleTime` do serviço `IOHIDSystem` via IOKit e devolve
segundos. Sem shell out para `ioreg`. Única dependência: IOKit.

**ActivityDeclarer** — encapsula `IOPMAssertionDeclareUserActivity`, mantendo o
`IOPMAssertionID` entre chamadas para reaproveitar a assertion. Reporta falha
em vez de silenciá-la.

**SyntheticInput** — posta key down + key up de F15 (`kVK_F15`, código 0x71) via
`CGEvent` no `.cghidEventTap`. Expõe consulta ao estado da permissão
(`AXIsProcessTrusted`) e uma ação que abre o painel de Ajustes correspondente.
A permissão é reconsultada a cada ciclo, para que conceder autorização com o app
aberto passe a valer sem reinício.

**LockMonitor** — observa `com.apple.screenIsLocked` e
`com.apple.screenIsUnlocked` no `DistributedNotificationCenter`.

**Preferences** — persiste em `UserDefaults` o intervalo de auto-off e a
preferência de abrir com o sistema. O estado ligado/desligado **não** é
persistido: o app sempre inicia desligado.

**PresenceController** — orquestra o laço, mantém o estado e o publica para a
UI. Recebe as dependências por protocolo, para permitir substitutos nos testes.

## Estados

| Estado | Significado |
|---|---|
| `off` | Toggle desligado. Nenhuma ação. |
| `active(.declared)` | Laço rodando via power assertion, sem permissões. |
| `active(.synthetic)` | Laço rodando com input sintético, após escalonamento. |
| `blocked` | Escalonamento necessário, mas a permissão de Acessibilidade foi negada. O app não consegue cumprir sua função e diz isso. |
| `pausedLocked` | Tela bloqueada. Toggle segue ligado, laço suspenso. |

## Laço principal

Executa a cada 30 segundos enquanto ligado e não pausado:

1. `ActivityDeclarer.declare()` (sempre, nos dois modos)
2. Em `.synthetic`, também `SyntheticInput.tap()`
3. Aguarda 1 segundo
4. Lê `IdleReader.seconds()`
5. Idle < 5s → contador de falhas zerado
6. Idle >= 5s em 3 ciclos consecutivos → escala para `.synthetic`; se a
   permissão for negada, vai para `blocked`

Margem de segurança: o Teams marca ausente por volta de 5 minutos de
ociosidade. Um ciclo de 30s com escalonamento em 3 falhas leva no máximo ~93s
para corrigir o modo — bem dentro da janela. Os números não são arbitrários.

**App Nap.** Um app `LSUIElement` em segundo plano sofre coalescing de timers, e
um atraso grande no laço derrubaria a garantia acima. O laço é uma `Task` com
`Task.sleep` entre os ciclos, e o app mantém um
`ProcessInfo.beginActivity(options: .userInitiated)` enquanto ativo — é o
`beginActivity` que impede o adiamento, não o tipo de timer.

## Interface

Menu da barra:

- **Manter disponível** — toggle principal
- **Estado** — `Ativo · inatividade 2s`, `Ativo (modo estendido)`,
  `Pausado (tela bloqueada)`, `Precisa de permissão` ou `Desligado`. O valor de
  inatividade é atualizado ao vivo e serve como evidência visível.
- **Conceder permissão de Acessibilidade** — visível apenas em `blocked`; abre o
  painel de Ajustes.
- **Desligar automaticamente após** — Nunca / 1h / 4h / 8h (padrão: 8h)
- **Abrir com o sistema** — via `SMAppService`
- **Sair**

O ícone da barra é um círculo cheio quando ativo, contornado quando desligado e
com barra diagonal em `blocked`. Ícone template, para acompanhar tema claro e
escuro.

Todo o diagnóstico vai também para `OSLog` (subsystem `com.carlos.presence`),
para investigar um "por que ficou amarelo às 15h" depois do fato.

## Erros e casos de borda

- **Assertion falha** (erro do IOKit) → escala imediatamente, sem esperar os 3
  ciclos. O app nunca reporta "ativo" sem ter verificado.
- **Permissão negada** → estado `blocked`, com botão que abre Ajustes. O app não
  finge estar funcionando.
- **Tela bloqueada manualmente** → `pausedLocked`. Sem isso, a declaração de
  atividade reacenderia o display, deixando o Mac aceso a noite toda depois de
  Carlos sair. Com a tela bloqueada o Teams marca ausente de qualquer forma, então
  a pausa não custa nada. Ao desbloquear, o laço retoma sozinho — o toggle
  nunca foi desligado.
- **Sleep do Mac** (tampa fechada ou sleep manual) → o app não tenta impedir. Ao
  acordar, retoma se ainda estiver dentro do intervalo de auto-off.
- **Auto-off** é calculado por tempo de parede: guarda o `Date` de início e
  compara com o presente. Contar ciclos faria 3h de sleep não contarem, e o app
  ficaria ligado muito além do pretendido.
- **Início** → sempre desligado. Nunca liga sozinho.

## Testes

- **IdleReader** (integração): confirma que a leitura devolve um valor plausível
  (>= 0 e < 24h) e que cresce ao longo de 2s sem input. O teste detecta
  contaminação por atividade humana concorrente (queda no valor) e é marcado
  como skip nesse caso, em vez de falhar por ruído — foi exatamente esse ruído
  que invalidou a medição inicial.
- **PresenceController** (unitário, dependências falsas, relógio injetado):
  escala para `.synthetic` na terceira leitura consecutiva >= 5s e não na
  segunda; volta a zerar o contador em uma leitura boa; falha da assertion
  escala imediatamente; permissão negada leva a `blocked`; bloqueio de tela leva
  a `pausedLocked` e o desbloqueio retoma; auto-off dispara por tempo de parede,
  inclusive com um salto de relógio simulando sleep; estado inicial é `off`.
- **SyntheticInput**: teste manual documentado — sem permissão concedida o
  `CGEvent.post` falha silenciosamente, então o teste automatizado seria um
  falso positivo.
- **Manual, ao final**: ligar, deixar o Mac parado por 15 minutos, confirmar que
  o Teams permanece verde e que o `HIDIdleTime` no menu se manteve baixo.

## Definição de pronto — concluída em 2026-09-09

1. ✅ **Experimento de verificação.** Duas medições, a segunda limpa, registradas
   acima. A power assertion não zera o `HIDIdleTime`.
2. ✅ **Testes automatizados.** 37 testes, 0 falhas.
3. ✅ **App instalado** em `/Applications`, aberto pelo usuário.
4. ✅ **Teste de ponta a ponta.** Mais de 40 minutos com o Teams verde,
   confirmado pelo usuário e corroborado por amostragem independente do
   `HIDIdleTime` a cada 15s:

```
09:09-09:11   16 → 31 → 46 → 6 → 21 → 36 → 51 → 66 → 81 → 96 → 111   (app ainda não agindo)
09:12:05      0,4                                                     (passa a agir)
09:13-09:29   13 → 28 → 10 → 26 → 8 → 23 → 6 → 21 → 4 → 19 → 1 → 16  (dente de serra)
```

O contador nunca ultrapassa **31,9s** depois de estabilizar — exatamente o ciclo
de 30s mais o 1s de verificação. O padrão é mecânico, não humano: uso real
manteria o idle irregular e quase sempre em zero.

O app se estabilizou no modo **`.synthetic`**, como a verificação previa.

Esta é a primeira observação direta do mecanismo central funcionando. Até aqui,
os testes provavam a lógica em volta do F15, não o F15.

## Fora de escopo

Agenda por horário, integração com a API do Teams, detecção de reunião,
histórico de uso.
