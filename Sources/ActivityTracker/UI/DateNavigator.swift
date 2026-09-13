import SwiftUI

/// A pill-shaped prev/date/next control — replaces the stock `DatePicker`
/// (`.compact` style renders as a raw numeric stepper, which reads as noticeably
/// more "OS control panel" than the rest of the app). Tapping the date opens a
/// proper calendar popover instead.
struct DateNavigator: View {
    @Binding var selectedDay: Date
    @State private var showingCalendar = false

    var body: some View {
        HStack(spacing: 2) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(SubtleIconButtonStyle())

            Button {
                showingCalendar = true
            } label: {
                Text(selectedDay.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 92)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                DatePicker(
                    "",
                    selection: $selectedDay,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(10)
                .frame(width: 270)
                .onChange(of: selectedDay) { _, _ in showingCalendar = false }
            }

            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(SubtleIconButtonStyle())
                .disabled(Calendar.current.isDateInToday(selectedDay))
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.04)))
    }

    private func shift(_ delta: Int) {
        if let newDay = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay) {
            selectedDay = min(newDay, Date())
        }
    }
}
