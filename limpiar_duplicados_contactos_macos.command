#!/bin/zsh
set -e

# macOS Contact Duplicate Cleaner
# Limpia duplicados de Apple Contacts usando Contacts.framework.
#
# Modos:
# 1) SEGURO: mismo nombre + mismos teléfonos + mismos correos
# 2) AGRESIVO: mismo nombre visible, conserva el contacto más completo
#
# Ejecutar con:
#   zsh limpiar_duplicados_contactos_macos.command
#
# El script genera un CSV previo con los contactos que planea borrar.

WORKDIR="$HOME/Desktop/Contactos_Duplicados_Backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WORKDIR"

SWIFT_FILE="$WORKDIR/limpiar_duplicados_contactos.swift"

cat > "$SWIFT_FILE" <<'SWIFT'
import Foundation
import Contacts

enum Mode {
    case safe
    case aggressive
}

func runAppleScript(_ source: String) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", source]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func chooseMode() -> Mode? {
    let result = runAppleScript("""
    set opts to {"SEGURO: mismo nombre + mismos teléfonos/correos", "AGRESIVO: mismo nombre visible"}
    try
        choose from list opts with title "Limpiar duplicados de Contactos" with prompt "Elige modo. Primero usa SEGURO. Si quedan A1/AB repetidos, usa AGRESIVO." default items {item 1 of opts}
    on error
        return "CANCEL"
    end try
    """)
    if result.contains("AGRESIVO") { return .aggressive }
    if result.contains("SEGURO") { return .safe }
    return nil
}

func dialog(_ msg: String) {
    let escaped = msg.replacingOccurrences(of: "\"", with: "\\\"")
    _ = runAppleScript("display dialog \"\(escaped)\" buttons {\"OK\"} default button \"OK\"")
}

func confirmDelete(count: Int, mode: Mode, examples: [String], backupPath: String) -> Bool {
    let modeText = mode == .safe ? "SEGURO" : "AGRESIVO"
    let exampleText = examples.prefix(12).joined(separator: "\\n").replacingOccurrences(of: "\"", with: "\\\"")
    let backupEsc = backupPath.replacingOccurrences(of: "\"", with: "\\\"")
    let script = """
    set msg to "Modo: \(modeText)\\n\\nSe van a borrar \(count) contactos duplicados. Se conservará el contacto más completo de cada grupo.\\n\\nEjemplos:\\n\(exampleText)\\n\\nCSV previo:\\n\(backupEsc)\\n\\n¿Borrar ahora?"
    display dialog msg buttons {"Cancelar", "BORRAR \(count)"} default button "Cancelar" with icon caution
    if button returned of result starts with "BORRAR" then
        return "YES"
    else
        return "NO"
    end if
    """
    return runAppleScript(script).contains("YES")
}

func normalize(_ value: String) -> String {
    value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

func normalizePhone(_ value: String) -> String {
    value.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
}

func visibleName(_ c: CNContact) -> String {
    let name = [c.givenName, c.middleName, c.familyName]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if !name.isEmpty { return name }
    if !c.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c.nickname }
    if !c.organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c.organizationName }
    return "(sin nombre)"
}

func phones(_ c: CNContact) -> [String] {
    Array(Set(c.phoneNumbers.map { normalizePhone($0.value.stringValue) }.filter { !$0.isEmpty })).sorted()
}

func emails(_ c: CNContact) -> [String] {
    Array(Set(c.emailAddresses.map { normalize(String($0.value)) }.filter { !$0.isEmpty })).sorted()
}

func score(_ c: CNContact) -> Int {
    var s = 0
    let textFields = [
        c.givenName, c.middleName, c.familyName, c.nickname,
        c.organizationName, c.departmentName, c.jobTitle
    ]
    for f in textFields where !f.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s += 2 }
    s += c.phoneNumbers.count * 5
    s += c.emailAddresses.count * 5
    s += c.postalAddresses.count * 3
    s += c.urlAddresses.count * 2
    s += c.socialProfiles.count * 2
    s += c.dates.count
    if c.imageDataAvailable { s += 2 }
    return s
}

func groupKey(_ c: CNContact, mode: Mode) -> String {
    let name = normalize(visibleName(c))
    if mode == .aggressive {
        return "name:\(name)"
    }
    return [
        "safe",
        normalize(c.givenName),
        normalize(c.middleName),
        normalize(c.familyName),
        normalize(c.nickname),
        normalize(c.organizationName),
        "p=\(phones(c).joined(separator: ","))",
        "e=\(emails(c).joined(separator: ","))"
    ].joined(separator: "|")
}

func csvEscape(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

guard let mode = chooseMode() else {
    print("Cancelado.")
    exit(0)
}

let store = CNContactStore()
let status = CNContactStore.authorizationStatus(for: .contacts)

if status == .notDetermined {
    let sem = DispatchSemaphore(value: 0)
    var granted = false
    store.requestAccess(for: .contacts) { ok, _ in
        granted = ok
        sem.signal()
    }
    sem.wait()
    if !granted {
        dialog("Permiso denegado. Activa Terminal en Configuración del Sistema → Privacidad y seguridad → Contactos.")
        exit(1)
    }
} else if status != .authorized {
    dialog("Terminal no tiene permiso de Contactos. Actívalo en Configuración del Sistema → Privacidad y seguridad → Contactos.")
    exit(1)
}

let keys: [CNKeyDescriptor] = [
    CNContactIdentifierKey as CNKeyDescriptor,
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactMiddleNameKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactNicknameKey as CNKeyDescriptor,
    CNContactOrganizationNameKey as CNKeyDescriptor,
    CNContactDepartmentNameKey as CNKeyDescriptor,
    CNContactJobTitleKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactPostalAddressesKey as CNKeyDescriptor,
    CNContactUrlAddressesKey as CNKeyDescriptor,
    CNContactSocialProfilesKey as CNKeyDescriptor,
    CNContactDatesKey as CNKeyDescriptor,
    CNContactImageDataAvailableKey as CNKeyDescriptor
]

var contacts: [CNContact] = []
let request = CNContactFetchRequest(keysToFetch: keys)
try store.enumerateContacts(with: request) { contact, _ in
    contacts.append(contact)
}

var groups: [String: [CNContact]] = [:]
for c in contacts {
    let k = groupKey(c, mode: mode)
    if k == "name:" { continue }
    groups[k, default: []].append(c)
}

var toDelete: [CNContact] = []
var examples: [String] = []

for (_, arr) in groups where arr.count > 1 {
    let sorted = arr.sorted { score($0) > score($1) }
    let keep = sorted[0]
    let deletes = Array(sorted.dropFirst())
    toDelete.append(contentsOf: deletes)
    if examples.count < 12 {
        examples.append("\(visibleName(keep)) → borrar \(deletes.count), conservar 1")
    }
}

let backupPath = "\(FileManager.default.currentDirectoryPath)/contactos_a_borrar.csv"
var csv = "nombre,telefonos,correos,identificador,puntuacion\\n"
for c in toDelete {
    csv += [
        csvEscape(visibleName(c)),
        csvEscape(phones(c).joined(separator: " | ")),
        csvEscape(emails(c).joined(separator: " | ")),
        csvEscape(c.identifier),
        csvEscape(String(score(c)))
    ].joined(separator: ",") + "\\n"
}
try csv.write(toFile: backupPath, atomically: true, encoding: .utf8)

if toDelete.isEmpty {
    dialog("No encontré duplicados con este modo. Prueba AGRESIVO si tienes contactos repetidos visualmente tipo A1, AB, etc.")
    exit(0)
}

guard confirmDelete(count: toDelete.count, mode: mode, examples: examples, backupPath: backupPath) else {
    print("Cancelado. No se borró nada.")
    exit(0)
}

let save = CNSaveRequest()
for c in toDelete {
    save.delete(c.mutableCopy() as! CNMutableContact)
}
try store.execute(save)

dialog("Listo. Se borraron \(toDelete.count) contactos duplicados. Espera unos minutos a que iCloud sincronice. CSV previo: \(backupPath)")
print("Listo. Borrados: \(toDelete.count)")
SWIFT

echo "Ejecutando limpiador de duplicados..."
cd "$WORKDIR"
/usr/bin/swift "$SWIFT_FILE"
echo ""
echo "Carpeta generada: $WORKDIR"
echo "Presiona Enter para cerrar."
read
