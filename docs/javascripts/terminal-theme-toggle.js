;(() => {
  const STORAGE_KEY = "doc-home-ops-terminal-palette"
  const DEFAULT = "default"
  const DARK = "dark"

  const getStoredPalette = () => {
    try {
      return localStorage.getItem(STORAGE_KEY)
    } catch {
      return null
    }
  }

  const setStoredPalette = (palette) => {
    try {
      localStorage.setItem(STORAGE_KEY, palette)
    } catch {
      // Ignore storage failures.
    }
  }

  const systemPrefersDark = () =>
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches

  const findPaletteLink = () =>
    document.querySelector('link[href*="css/palettes/"][rel="stylesheet"]')

  const updateButton = (button, palette) => {
    if (!button) {
      return
    }
    const next = palette === DARK ? DEFAULT : DARK
    const icon = palette === DARK ? "☀" : "☾"
    const label = next === DARK ? "Dark" : "Light"
    button.textContent = `${icon} ${label}`
    button.title = `Switch to ${label.toLowerCase()} mode`
    button.setAttribute("aria-label", button.title)
  }

  const applyPalette = (palette, button) => {
    const link = findPaletteLink()
    if (!link) {
      return
    }

    const nextHref = link.href.replace(
      /\/(default|dark)\.css$/,
      `/${palette}.css`
    )
    if (nextHref !== link.href) {
      link.href = nextHref
    }

    document.documentElement.dataset.palette = palette
    updateButton(button, palette)
  }

  const insertToggleButton = () => {
    const menu = document.querySelector(".terminal-menu > ul")
    if (!menu) {
      return null
    }

    const li = document.createElement("li")
    li.setAttribute("property", "itemListElement")
    li.setAttribute("typeof", "ListItem")

    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "terminal-theme-toggle-btn"
    li.appendChild(btn)
    menu.appendChild(li)

    return btn
  }

  const init = () => {
    const button = insertToggleButton()
    const preferred =
      getStoredPalette() || (systemPrefersDark() ? DARK : DEFAULT)
    applyPalette(preferred, button)

    if (button) {
      button.addEventListener("click", () => {
        const current =
          document.documentElement.dataset.palette === DARK ? DARK : DEFAULT
        const next = current === DARK ? DEFAULT : DARK
        applyPalette(next, button)
        setStoredPalette(next)
      })
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init)
  } else {
    init()
  }
})()
