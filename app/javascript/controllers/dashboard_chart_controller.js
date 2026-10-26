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
    const muted = "#8a827c"
    const palette = ["#9a6f72", "#1a1716", "#c4a0a3", "#4a4340", "#f8cdd0", "#8a827c"]
    const doughnut = config.type === "doughnut"
    const number = new Intl.NumberFormat(document.documentElement.lang || "en")
    const money = new Intl.NumberFormat(document.documentElement.lang || "en", {
      minimumFractionDigits: 2, maximumFractionDigits: 2
    })
    const formatMoney = value => `${money.format(value)} ${this.currencyValue}`

    config.data.datasets.forEach((dataset, index) => {
      if (doughnut) {
        dataset.backgroundColor ||= config.data.labels.map((_, item) => palette[item % palette.length])
        dataset.borderColor = "#faf9f7"
        dataset.borderWidth = 3
        dataset.hoverOffset = 5
      } else {
        dataset.borderColor = index === 0 ? foreground : "#9a6f72"
        dataset.backgroundColor = index === 0 ? "rgba(26, 23, 22, 0.07)" : "#9a6f72"
        dataset.borderWidth = index === 0 ? 3 : 2
        dataset.pointRadius = 0
        dataset.pointHoverRadius = 4
        dataset.pointHitRadius = 12
        dataset.tension = 0.35
        dataset.fill = index === 0 ? "origin" : false
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
        legend: {
          display: !doughnut,
          position: "bottom",
          align: "start",
          rtl,
          textDirection: rtl ? "rtl" : "ltr",
          labels: { color: foreground, usePointStyle: true, pointStyle: "line", padding: 18 }
        },
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
    if (doughnut) {
      config.options.cutout = "68%"
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
