import Foundation

// MARK: - Region

enum Region: String, CaseIterable, Identifiable {
    case auSydney = "au-sy"
    case caToronto = "ca-tr"
    case dkCopenhagen = "dk-co"
    case deFrankfurt = "de-fr"
    case ukLondon = "uk-ld"
    case usDC = "us-dc"
    case chZurich = "ch-zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auSydney: return "Australia (Sydney)"
        case .caToronto: return "Canada (Toronto)"
        case .dkCopenhagen: return "Denmark (Copenhagen)"
        case .deFrankfurt: return "Germany (Frankfurt)"
        case .ukLondon: return "UK (London)"
        case .usDC: return "US (Washington DC)"
        case .chZurich: return "Switzerland (Zurich)"
        }
    }

    var baseURL: URL {
        URL(string: "https://\(rawValue).keepit.com")!
    }
}

// MARK: - Credential

struct Credential: Codable {
    let region: Region
    let username: String
    let password: String
}

extension Region: Codable {}

// MARK: - Connector

struct Connector: Identifiable {
    let id: String          // GUID
    let name: String
    let type: ConnectorType
    let created: Date
    var health: HealthStatus
    var healthReason: String?
    var lastSnapshotTime: Date?
    var lastSnapshotSize: Int64?
    var hasAnomaly: Bool = false
}

enum ConnectorType: String {
    // Raw values match what the Keepit API returns
    case m365 = "o365-admin"
    case dynamics365 = "dynamics365"
    case salesforce = "sforce"
    case google = "gsuite"
    case powerBI = "powerbi"
    case zendesk = "zendesk"
    case azureDevOps = "azure-do"
    case entraID = "azure-ad"
    // DSL sub-types (from agent-type field)
    case exchange, sharePoint = "sharepoint", oneDrive = "onedrive", teams
    case unknown

    var displayName: String {
        switch self {
        case .m365: return "Microsoft 365"
        case .dynamics365: return "Dynamics 365"
        case .salesforce: return "Salesforce"
        case .google: return "Google Workspace"
        case .powerBI: return "Power BI"
        case .zendesk: return "Zendesk"
        case .azureDevOps: return "Azure DevOps"
        case .entraID: return "Entra ID"
        case .exchange: return "Exchange"
        case .sharePoint: return "SharePoint"
        case .oneDrive: return "OneDrive"
        case .teams: return "Teams"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .m365: return "square.grid.2x2.fill"
        case .dynamics365: return "chart.bar.fill"
        case .salesforce: return "cloud.fill"
        case .google: return "g.circle.fill"
        case .powerBI: return "chart.pie.fill"
        case .zendesk: return "headphones.circle.fill"
        case .azureDevOps: return "hammer.fill"
        case .entraID: return "person.badge.key.fill"
        case .exchange: return "envelope.fill"
        case .sharePoint: return "doc.fill"
        case .oneDrive: return "icloud.fill"
        case .teams: return "person.3.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum HealthStatus: String {
    case healthy, unhealthy, critical, unknown

    var color: String {
        switch self {
        case .healthy: return "green"
        case .unhealthy: return "yellow"
        case .critical: return "red"
        case .unknown: return "gray"
        }
    }
}
