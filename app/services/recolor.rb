# frozen_string_literal: true

# Recolors a garment inside a photograph. The Python service segments the
# product, shifts its color in Lab, and composites it back so the scene
# outside the mask stays byte-for-byte identical.
module Recolor
  class Error < StandardError; end

  HEX = /\A#([0-9A-Fa-f]{6})\z/

  PRESETS = [
    { name: "Baby pink", hex: "#F4C2C2" }.freeze,
    { name: "Black", hex: "#1A1716" }.freeze,
    { name: "Taupe", hex: "#9A8B7A" }.freeze,
    { name: "Ocean blue", hex: "#1F4E79" }.freeze
  ].freeze

  module_function

  def normalize_hex(value)
    raw = value.to_s.strip
    raw = "##{raw}" unless raw.start_with?("#")
    raise Error, "Enter a color as a hex value, for example #F4C2C2." unless raw.match?(HEX)

    "##{raw[1..].upcase}"
  end
end
