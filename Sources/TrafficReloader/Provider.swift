import Foundation

enum Provider: String, CaseIterable, Codable {
    case sim24 = "sim24"
    case simDe = "sim_de"
    case handyvertrag = "handyvertrag"
    case winsim = "winsim"
    case premiumsim = "premiumsim"
    case smartmobil = "smartmobil"
    case yourfone = "yourfone"
    case blacksim = "blacksim"
    case cybersim = "cybersim"
    case maxxim = "maxxim"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .sim24: return "SIM24 (service.sim24.de)"
        case .simDe: return "sim.de (service.sim.de)"
        case .handyvertrag: return "Handyvertrag.de (service.handyvertrag.de)"
        case .winsim: return "WinSIM (service.winsim.de)"
        case .premiumsim: return "PremiumSIM (service.premiumsim.de)"
        case .smartmobil: return "smartmobil.de (service.smartmobil.de)"
        case .yourfone: return "yourfone (service.yourfone.de)"
        case .blacksim: return "BlackSIM (service.blacksim.de)"
        case .cybersim: return "CyberSIM (service.cyber-sim.de)"
        case .maxxim: return "maXXim (service.maxxim.de)"
        case .custom: return "Custom Servicewelt Domain"
        }
    }

    var defaultHost: String {
        switch self {
        case .sim24: return "https://service.sim24.de"
        case .simDe: return "https://service.sim.de"
        case .handyvertrag: return "https://service.handyvertrag.de"
        case .winsim: return "https://service.winsim.de"
        case .premiumsim: return "https://service.premiumsim.de"
        case .smartmobil: return "https://service.smartmobil.de"
        case .yourfone: return "https://service.yourfone.de"
        case .blacksim: return "https://service.blacksim.de"
        case .cybersim: return "https://service.cyber-sim.de"
        case .maxxim: return "https://service.maxxim.de"
        case .custom: return ""
        }
    }
}
