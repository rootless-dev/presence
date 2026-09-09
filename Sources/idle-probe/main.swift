import Foundation
import PresenceCore

// Experimento: a power assertion zera o HIDIdleTime?
//
// Espera a máquina ficar de fato ociosa por 60s — sem depender de o operador
// ficar parado numa janela combinada, que foi o que contaminou a medição
// manual feita durante o design.

let reader = IdleReader()
let declarer = ActivityDeclarer()

let threshold: TimeInterval = 60
let deadline = Date().addingTimeInterval(3600)

print("aguardando \(Int(threshold))s de ociosidade real (até 1h)...")

while Date() < deadline {
    guard reader.idleSeconds() >= threshold else {
        Thread.sleep(forTimeInterval: 5)
        continue
    }

    let before = reader.idleSeconds()
    do {
        try declarer.declare()
    } catch {
        print("FALHA ao declarar atividade: \(error)")
        exit(1)
    }
    Thread.sleep(forTimeInterval: 1)
    let after = reader.idleSeconds()

    print(String(format: "idle ANTES = %.1fs | DEPOIS = %.1fs", before, after))

    if after < 5 {
        print("RESULTADO: a assertion ZERA o contador. Modo .declared é viável.")
    } else if after >= before {
        print("RESULTADO: a assertion NÃO zera o contador. O app viverá em .synthetic.")
    } else {
        print("RESULTADO: inconclusivo (queda parcial). Repetir a sonda.")
    }
    exit(0)
}

print("desisti: a máquina não ficou ociosa por \(Int(threshold))s em 1 hora")
exit(2)
