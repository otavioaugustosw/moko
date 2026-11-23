import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Use SQL wall-clock components; choosing a date never converts the server's
// displayed time through the Mac's time zone or drops fractional seconds.
struct NativeSQLDatePicker: NSViewRepresentable {
    let kind: SQLTemporalKind
    @Binding var value: Date
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerMode = .single
        picker.datePickerElements =
            kind == .date
            ? [.yearMonthDay]
            : (kind == .time ? [.hourMinuteSecond] : [.yearMonthDay, .hourMinuteSecond])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SQLTemporalKind.zone
        picker.calendar = calendar
        picker.timeZone = SQLTemporalKind.zone
        picker.focusRingType = .none
        picker.locale = Locale(identifier: "en_US")
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.dateValue = value
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if abs(picker.dateValue.timeIntervalSince(value)) > 0.001 { picker.dateValue = value }
    }
    final class Coordinator: NSObject {
        var parent: NativeSQLDatePicker
        var updating = false
        init(_ parent: NativeSQLDatePicker) { self.parent = parent }
        @objc func changed(_ picker: NSDatePicker) {
            guard !updating else { return }
            parent.value = picker.dateValue
        }
    }
}
