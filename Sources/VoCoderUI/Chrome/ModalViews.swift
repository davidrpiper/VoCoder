// How the modals look: a centred box per modal, the top one drawn last. Each is a trap focus
// scope, so focus stays inside until it is answered.
import VoCoderCore

struct ModalsView: View {
  let presenter: ModalPresenter

  var body: some View {
    for modal in presenter.stack {
      ModalView(presenter: presenter, modal: modal)
    }
  }
}

struct ModalView: View {
  static let width = 56

  let presenter: ModalPresenter
  let modal: ModalPresenter.Modal

  var body: some View {
    VStack {
      Spacer()
      HStack {
        Spacer()
        content
          .border(.rounded, title: title, color: .focus)
          .frame(width: .exactly(Self.width))
          .clearUnder()
        Spacer()
      }
      Spacer()
    }
    .focusScope(modal.scopeID, trap: true) { [presenter, modal] in presenter.handle($0, in: modal) }
  }

  private var title: String {
    switch modal.kind {
    case .confirm(let request): request.title
    case .text(let request): request.title
    case .choice(let request): request.title
    }
  }

  @ViewBuilder private var content: some View {
    switch modal.kind {
    case .confirm(let request): confirm(request)
    case .text(let request): text(request)
    case .choice: choice
    }
  }

  private func confirm(_ request: ConfirmRequest) -> some View {
    VStack {
      for line in request.message.split(separator: "\n", omittingEmptySubsequences: false) {
        Paragraph(String(line))
      }
      Text("")
      HStack {
        Spacer()
        Button(modal.cancelButtonID, request.cancelTitle) { [presenter] in
          presenter.answerConfirm(false)
        }
        Text("  ")
        Button(modal.confirmButtonID, request.confirmTitle) { [presenter] in
          presenter.answerConfirm(true)
        }
      }
      Text("y confirm · n / Esc cancel · ←→ choose").foreground(.muted)
    }
  }

  private func text(_ request: TextRequest) -> some View {
    VStack {
      HStack {
        Text("› ").foreground(.accent)
        TextField(
          modal.fieldID, placeholder: request.placeholder,
          onSubmit: { [presenter] in presenter.submit($0) })
      }
      Divider()
      Text("Enter submit · Esc cancel").foreground(.muted)
    }
  }

  private var choice: some View {
    let choices = modal.filteredChoices
    let selected = modal.list.selectedIndex(count: choices.count)
    let rows = 8
    let start =
      choices.count > rows ? min(max((selected ?? 0) - rows + 1, 0), choices.count - rows) : 0
    let window = start..<min(choices.count, start + rows)
    return VStack {
      HStack {
        Text("› ").foreground(.accent)
        TextField(
          modal.fieldID, placeholder: "Filter",
          onChange: { [presenter] in presenter.queryChanged($0) },
          onSubmit: { [presenter] in presenter.submit($0) })
      }
      Divider()
      if choices.isEmpty {
        Text("No matches").foreground(.muted)
      }
      for index in window {
        HStack {
          Text(index == selected ? "› " : "  ")
          Text(choices[index].title)
          Spacer()
        }
        .foreground(index == selected ? .selectionText : nil)
        .background(index == selected ? .selection : nil)
      }
      Text(
        (choices.count > rows ? "\(choices.count) choices · " : "")
          + "↑↓ select · Enter choose · Esc cancel"
      )
      .foreground(.muted)
    }
  }
}
