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

## Abordagem

O app declara atividade do usuário via IOKit
(`IOPMAssertionDeclareUserActivity` com `kIOPMUserActiveLocal`) e **verifica o
resultado** lendo o `HIDIdleTime`. A declaração não exige nenhuma permissão do
macOS e não injeta input, mas não há garantia documentada de que zere o
contador que o Teams observa. Por isso a verificação é parte do produto, não
uma suposição.

Se a verificação mostrar que o contador continua subindo, o app escala para
input sintético (`CGEvent` de tecla F15 — inexistente em teclados Mac, nenhum
app reage a ela), que zera o contador com certeza mas exige permissão de
Acessibilidade.

Ordem de privilégio: o caminho sem permissão é sempre tentado primeiro; a
permissão só é pedida quando comprovadamente necessária.

## Arquitetura

```
PresenceApp (SwiftUI, MenuBarExtra, LSUIElement)
   └── PresenceController      — máquina de estados: off / active / degraded
         ├── ActivityDeclarer  — IOPMAssertionDeclareUserActivity
         ├── IdleReader        — HIDIdleTime via IOHIDSystem (IOKit direto)
         ├── SyntheticInput    — CGEvent F15 (fallback)
         └── AutoOffTimer      — desligamento automático
```

Build: Swift Package Manager + script de empacotamento do `.app`. Sem projeto
Xcode, para manter tudo em texto versionável.

### Componentes

**IdleReader** — lê `HIDIdleTime` do serviço `IOHIDSystem` via IOKit e devolve
segundos. Sem shell out para `ioreg`. Única dependência: IOKit.

**ActivityDeclarer** — encapsula `IOPMAssertionDeclareUserActivity`, mantendo o
`IOPMAssertionID` entre chamadas para reaproveitar a assertion. Reporta falha
em vez de silenciá-la.

**SyntheticInput** — posta key down + key up de F15 via `CGEvent`. Expõe
consulta ao estado da permissão de Acessibilidade (`AXIsProcessTrusted`) e uma
ação que abre o painel de Ajustes correspondente.

**AutoOffTimer** — dispara desligamento após o intervalo escolhido.

**PresenceController** — orquestra o laço, mantém o estado e publica o estado
para a UI. Recebe as dependências por protocolo, para permitir substitutos nos
testes.

## Laço principal

Executa a cada 30 segundos enquanto ligado:

1. `ActivityDeclarer.declare()`
2. Aguarda 1 segundo
3. Lê `IdleReader.seconds()`
4. Idle < 5s → estado `active`
5. Idle >= 5s em 3 ciclos consecutivos → estado `degraded`: garante permissão
   de Acessibilidade e passa a chamar `SyntheticInput` a cada ciclo, mantendo a
   assertion junto. Qualquer leitura < 5s zera o contador de falhas.

O limite de 3 ciclos evita troca de modo por causa de uma leitura isolada.

## Interface

Menu da barra:

- **Manter disponível** — toggle principal
- **Estado** — `Ativo · inatividade 2s`, `Ativo (modo estendido)` ou
  `Desligado`. O valor de inatividade é atualizado ao vivo e serve como
  evidência visível de que o app está funcionando.
- **Desligar automaticamente após** — Nunca / 1h / 4h / 8h (padrão: 8h)
- **Abrir com o sistema** — via `SMAppService`
- **Sair**

O ícone da barra é um círculo cheio quando ativo e contornado quando desligado.

## Erros e casos de borda

- Assertion retorna erro do IOKit → vai direto para `degraded`; o app nunca
  reporta "ativo" sem ter verificado.
- Permissão de Acessibilidade negada → estado `degraded (bloqueado)`, com botão
  no menu que abre o painel de Ajustes.
- Mac dorme por tampa fechada ou sleep manual → o app não tenta impedir; ao
  acordar, retoma o laço se ainda estiver dentro do intervalo do auto-off.
- Ao iniciar, o app sempre começa desligado. Nunca liga sozinho.

## Testes

- **IdleReader** (integração real): lê o idle, provoca atividade, confirma que
  o valor caiu.
- **PresenceController** (unitário, com dependências falsas): transição para
  `degraded` apenas na terceira leitura consecutiva >= 5s, e não na segunda; retorno a `active` quando a
  assertion volta a funcionar; auto-off disparando no tempo correto; estado
  inicial desligado.
- **Manual, ao final**: ligar, deixar o Mac parado por 15 minutos, confirmar
  que o Teams permanece verde.

## Fora de escopo

Agenda por horário, integração com a API do Teams, detecção de reunião,
histórico de uso.
