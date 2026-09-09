# Presence

[![CI](https://github.com/rootless-dev/presence/actions/workflows/ci.yml/badge.svg)](https://github.com/rootless-dev/presence/actions/workflows/ci.yml)

App de barra de menus para macOS que mantém o status do Microsoft Teams em
**Disponível** enquanto está ligado.

## O problema

O Teams marca você como ausente com base no contador de inatividade do sistema
(`HIDIdleTime`, exposto pelo `IOHIDSystem`). Alguns minutos longe do teclado e o
status fica amarelo, mesmo que você esteja trabalhando na frente do computador.

## Como funciona

A cada 30 segundos o app age e então **confere se agiu**:

1. Declara atividade do usuário via IOKit (`IOPMAssertionDeclareUserActivity`, a
   mesma API por trás do `caffeinate -u`).
2. Espera um segundo e lê o `HIDIdleTime` de volta.
3. Se o contador não ceder em três ciclos seguidos, escala para injetar uma
   tecla **F15** sintética — uma tecla que não existe em teclados Mac e à qual
   nenhum aplicativo reage. Esse modo exige permissão de Acessibilidade.

O menu mostra o contador de inatividade real, em segundos. Dá para ver que está
funcionando em vez de torcer.

### O que a medição mostrou

A premissa inicial do projeto era que a power assertion do IOKit bastaria. Ela
não basta. Duas medições independentes, com a máquina comprovadamente ociosa:

```
caffeinate -u:  idle 63,7s  →  70,0s
idle-probe:     idle 857,8s →  858,8s
```

O contador seguiu subindo nas duas. **A declaração de atividade não zera o
`HIDIdleTime`** — nenhuma flag do `caffeinate` resolve esse problema. Por isso o
modo com a tecla sintética é o normal de operação, não a exceção.

A assertion continua sendo chamada a cada ciclo por outro motivo: é ela que
mantém a tela acesa e destravada, e tela bloqueada deixa o Teams amarelo de
qualquer forma. Os dois mecanismos são complementares.

Rode `make probe` para repetir a medição na sua máquina.

## Requisitos

- macOS 14 ou superior (Apple Silicon)
- Xcode com Swift 6.0+ para compilar
- Sem dependências externas — só frameworks do sistema

## Instalação

```bash
make install
open /Applications/Presence.app
```

No ícone da barra de menus, clique em **Ativar**. O macOS vai pedir permissão de
Acessibilidade: conceda em Ajustes do Sistema › Privacidade e Segurança ›
Acessibilidade e ative novamente. O menu deve passar a mostrar
`Ativo (modo estendido) · inatividade Ns`.

> Instale em `/Applications` antes de usar "Abrir com o sistema". O
> `SMAppService` guarda o caminho do bundle, e um login item registrado a partir
> da pasta de build quebra quando ela muda.

## Uso

```bash
make test      # roda a suíte de testes
make build     # compila em release
make bundle    # gera o Presence.app
make install   # instala em /Applications
make probe     # mede se a power assertion zera o contador nesta máquina
make clean     # limpa artefatos
```

## O que esperar

- **A tela não apaga nem bloqueia** enquanto o app está ativo. É o preço de
  parecer ativo: se a tela bloqueia, o Teams marca ausente de qualquer forma.
- **Com a tela bloqueada, o app pausa sozinho.** Declarar atividade acenderia o
  monitor, e ninguém quer o Mac aceso a noite toda. Ao desbloquear, ele retoma.
- **Desligamento automático** configurável: nunca, 1h, 4h ou 8h (padrão). Conta
  tempo de parede, então horas dormindo contam para o prazo.
- **O app sempre inicia desligado.** Nunca liga sozinho.
- **Cada rebuild com assinatura ad-hoc revoga a permissão de Acessibilidade**,
  porque o macOS vincula a permissão ao hash do binário. Para uma identidade
  estável: `DEV_ID="Developer ID Application: ..." make bundle`.

## Diagnóstico

```bash
log show --predicate 'subsystem == "com.carlos.presence"' --last 1h
```

O log registra as transições que respondem "por que o status ficou amarelo às
15h": quando ligou e em que modo, quando escalou, cada leitura de inatividade
alta com o número da falha, e quando desligou.

Para fazer o app esquecer o modo já verificado e redescobrir do zero:

```bash
defaults delete com.carlos.presence verifiedActivityMode
```

## Arquitetura

```
Sources/PresenceCore/     lógica, sem UI e sem dependência de ciclo de vida
  IdleReader              lê o HIDIdleTime via IOKit
  ActivityDeclarer        IOPMAssertionDeclareUserActivity
  SyntheticInput          tecla F15 via CGEvent, em .cghidEventTap
  LockMonitor             bloqueio e desbloqueio de tela
  Preferences             UserDefaults
  PresenceController      máquina de estados e laço de verificação

Sources/Presence/         camada de app
  PresenceApp             MenuBarExtra, LSUIElement
  PresenceRunner          ritmo de 30s, App Nap, ciclo de vida
  MenuView                o menu
  LoginItem               SMAppService

Sources/idle-probe/       a sonda de medição
```

Toda dependência de sistema entra por protocolo, então o laço inteiro roda nos
37 testes sem tocar no IOKit e sem esperar tempo real.

## Como isto foi verificado

Testes verdes não provam que um app deste tipo funciona — eles provam a lógica
em volta do mecanismo, não o mecanismo. A verificação de ponta a ponta foi
observar o `HIDIdleTime` de fora, a cada 15 segundos, com o app ativo e ninguém
tocando na máquina:

```
09:09-09:11   16 → 31 → 46 → 6 → 21 → 36 → 51 → 66 → 81 → 96 → 111   (app ainda não agindo)
09:12:05      0,4                                                     (passa a agir)
09:13-09:29   13 → 28 → 10 → 26 → 8 → 23 → 6 → 21 → 4 → 19 → 1 → 16  (dente de serra)
```

Depois de estabilizar, o contador nunca passou de **31,9s** — exatamente o ciclo
de 30s mais o segundo de verificação — com padrão mecânico, não humano. O Teams
permaneceu verde por mais de 40 minutos.

## Aviso

Algumas empresas têm políticas sobre ferramentas que alteram indicadores de
presença. Verifique as regras do seu empregador antes de usar.

## Licença

MIT — veja [LICENSE](LICENSE).
