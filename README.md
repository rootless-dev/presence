# Presence

App de barra de menus que mantém o status do Microsoft Teams em "Disponível"
enquanto está ligado.

## O problema

O Teams marca você como ausente com base no contador de inatividade do sistema
(`HIDIdleTime`). Sair do PC por alguns minutos deixa o status amarelo.

## Como funciona

A cada 30 segundos o app declara atividade do usuário via IOKit
(`IOPMAssertionDeclareUserActivity` — a mesma API do `caffeinate -u`) e então
**confere** o `HIDIdleTime` para ver se a declaração surtiu efeito. Se o
contador não ceder em três ciclos seguidos, o app escala para injetar uma tecla
F15 sintética, que não existe em teclados Mac e à qual nenhum app reage. Esse
modo estendido exige permissão de Acessibilidade.

O menu mostra o contador de inatividade real, então dá para ver que está
funcionando em vez de torcer.

Nesta máquina a medição já foi feita: a power assertion **não** zera o contador
(63,7s → 70,0s numa janela ociosa), então o modo estendido é o normal de
operação, não a exceção. A assertion continua sendo chamada a cada ciclo por
outro motivo: é ela que mantém a tela acesa e destravada, e tela bloqueada
deixa o Teams amarelo de qualquer forma.

## Uso

```bash
make test      # roda a suíte
make bundle    # gera Presence.app
make install   # instala em /Applications
make probe     # experimento: a power assertion zera o contador nesta máquina?
```

## Detalhes que importam

- Enquanto ativo, não há protetor de tela nem bloqueio automático. É o preço de
  parecer ativo.
- Com a tela bloqueada o app pausa sozinho: declarar atividade acenderia o
  monitor, e nesse estado o Teams marca ausente de qualquer forma. Desbloqueou,
  ele retoma.
- Cada rebuild com assinatura ad-hoc revoga a permissão de Acessibilidade. Para
  uma identidade estável: `DEV_ID="Developer ID Application: ..." make bundle`.
- O app sempre inicia desligado. Nunca liga sozinho.

## Diagnóstico

```bash
log show --predicate 'subsystem == "com.carlos.presence"' --last 1h
```

### Repetir a verificação nesta máquina

```bash
make probe
```

A sonda espera a máquina ficar 60 segundos ociosa de verdade (vá tomar um café)
e então mede se a power assertion zera o contador. Foi assim que se descobriu
que ela não zera.

### Esquecer o modo já verificado

O app guarda o modo que funcionou nesta máquina. Para forçá-lo a redescobrir do
zero:

```bash
defaults delete com.carlos.presence verifiedActivityMode
```
