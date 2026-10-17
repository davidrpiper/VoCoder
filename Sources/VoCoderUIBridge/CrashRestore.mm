// Terminal restore on Swift runtime traps. FTXUI restores the terminal on SIGSEGV/SIGABRT/
// SIGILL/SIGFPE/SIGBUS, but Swift's fatalError, failed force-unwraps and overflow traps raise
// SIGTRAP on arm64, which would leave the user's terminal in raw mode on the alternate screen.
#import "BridgeInternal.h"

#include <csignal>
#include <termios.h>
#include <unistd.h>

namespace {

struct termios gSavedTermios;
bool gHaveTermios = false;
struct sigaction gPreviousAction;
volatile sig_atomic_t gArmed = 0;

void OnTrap(int signal) {
  if (gArmed) {
    gArmed = 0;
    // Only async-signal-safe calls: write(2) and tcsetattr(3).
    static const char reset[] =
        "\x1b[0m"                                                   // attributes
        "\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[?1015l"  // mouse reporting
        "\x1b[?25h"                                                 // cursor visible
        "\x1b[?1049l"                                               // leave alternate screen
        "\r\n";
    (void)!write(STDOUT_FILENO, reset, sizeof reset - 1);
    if (gHaveTermios) tcsetattr(STDIN_FILENO, TCSANOW, &gSavedTermios);
  }
  // Die the way we would have: default action, then re-raise.
  struct sigaction fallback = {};
  fallback.sa_handler = SIG_DFL;
  sigemptyset(&fallback.sa_mask);
  sigaction(signal, &fallback, nullptr);
  raise(signal);
}

}  // namespace

void VCArmTrapRestore() {
  gHaveTermios = isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &gSavedTermios) == 0;
  struct sigaction action = {};
  action.sa_handler = OnTrap;
  sigemptyset(&action.sa_mask);
  sigaction(SIGTRAP, &action, &gPreviousAction);
  gArmed = 1;
}

void VCDisarmTrapRestore() {
  gArmed = 0;
  sigaction(SIGTRAP, &gPreviousAction, nullptr);
}
