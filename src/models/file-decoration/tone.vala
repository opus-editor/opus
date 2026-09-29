namespace FileDecoration {
  /**
   * Ordinal order is severity: a folder shows the highest tone found
   * anywhere beneath it (FileDecoration.Registry aggregates with int.max
   * over the ordinal), so NONE must stay 0 and the rest must stay
   * worst-last. Tones are semantic, mapped to libadwaita platform colors
   * by the row widget (SUCCESS=--success-color, WARNING=--warning-color,
   * ERROR=--error-color, ACCENT=--accent-color; ALERT is derived via
   * color-mix() instead — no libadwaita platform color is orange).
   */
  public enum Tone {
    NONE = 0,
    ACCENT,   // informational — e.g. a future "has incoming changes"
    SUCCESS,  // green — new/added
    WARNING,  // yellow — modified
    ALERT,    // orange — needs attention (merge conflict)
    ERROR;    // red — broken (a future linter-error badge)
  }
}
