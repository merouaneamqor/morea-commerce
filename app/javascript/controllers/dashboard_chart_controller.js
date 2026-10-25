import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js/auto"

// Each chart owns its canvas and is disposed before Turbo snapshots the page.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { config: Object, currency: String }

  connect() {
    this.destroyChart()
    this.beforeCache ||= this.destroyChart.bind(this)
    document.addEventListener("turbo:before-cache", this.beforeCache)

    const config = structuredClone(this.configValue)
    const style = getComputedStyle(this.element)
    const foreground = style.color
    const rtl = document.documentElement.dir === "rtl"
    const muted = "#9ca3af"
    const palette = [foreground, "#6b7280", muted, "#d1d5db", "#4b5563", "#e5e7eb"]
    const doughnut = config.type === "doughnut"
    const number = new Intl.NumberFormat(document.documentElement.lang || "en")
    const money = new Intl.NumberFormat(document.documentElement.lang || "en", {
      minimumFractionDigits: 2, maximumFractionDigits: 2
    })
    const formatMoney = value => `${money.format(value)} ${this.currencyValue}`

    config.data.datasets.forEach((dataset, index) => {
      if (doughnut) {
        dataset.backgroundColor = config.data.labels.map((_, item) => palette[item % palette.length])
        dataset.borderColor = style.backgroundColor
        dataset.borderWidth = 2
      } else {
        dataset.borderColor = index === 0 ? foreground : muted
        dataset.backgroundColor = dataset.borderColor
        dataset.borderWidth = 2
        dataset.pointRadius = 2
        dataset.pointHoverRadius = 5
        dataset.tension = 0.2
        dataset.fill = false
        if (index > 0) dataset.borderDash = [6, 4]
      }
    })

    const options = config.options || {}
    config.options = {
      ...options,
      responsive: true,
      maintainAspectRatio: false,
      animation: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? false : options.animation,
      color: foreground,
      font: { family: style.fontFamily },
      plugins: {
        ...options.plugins,
        legend: { display: !doughnut, rtl, textDirection: rtl ? "rtl" : "ltr", labels: { color: foreground, usePointStyle: true } },
        tooltip: {
          ...options.plugins?.tooltip,
          rtl,
          textDirection: rtl ? "rtl" : "ltr",
          callbacks: {
            label: context => {
              if (!doughnut) return `${context.dataset.label}: ${formatMoney(context.parsed.y)}`
              const total = context.dataset.data.reduce((sum, count) => sum + Number(count), 0)
              const percentage = total ? Number(context.raw) * 100 / total : 0
              return `${context.label}: ${number.format(context.raw)} (${number.format(Number(percentage.toFixed(1)))}%)`
            }
          }
        }
      }
    }
    if (!doughnut) {
      config.options.interaction = { mode: "index", intersect: false }
      config.options.scales = {
        x: { ticks: { color: foreground, maxTicksLimit: 8 }, grid: { display: false } },
        y: { beginAtZero: true, ticks: { color: foreground, callback: formatMoney }, grid: { color: "rgba(128,128,128,0.15)" } }
      }
    }
    this.chart = new Chart(this.canvasTarget, config)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.destroyChart()
  }

  destroyChart() {
    this.chart?.destroy()
    this.chart = null
  }
}
