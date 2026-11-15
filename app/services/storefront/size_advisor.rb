# frozen_string_literal: true

module Storefront
  # Estimates body measurements from height/weight/shape/fit preference, then
  # picks the closest garment size. Kept in Ruby so the scoring can be tested;
  # the Stimulus controller mirrors the same rules client-side so answers never
  # leave the shopper's browser.
  class SizeAdvisor
    BODY_SHAPES = {
      "slim" => { "chest" => 0.92, "waist" => 0.88, "hips" => 0.94 },
      "average" => { "chest" => 1.0, "waist" => 1.0, "hips" => 1.0 },
      "athletic" => { "chest" => 1.06, "waist" => 0.94, "hips" => 1.02 },
      "broad" => { "chest" => 1.1, "waist" => 1.08, "hips" => 1.08 }
    }.freeze

    FIT_PREFS = {
      "fitted" => -3.0,
      "regular" => 0.0,
      "relaxed" => 3.0
    }.freeze

    CUT_EASE = {
      "slim" => -2.0,
      "regular" => 0.0,
      "relaxed" => 2.0,
      "oversized" => 6.0
    }.freeze

    Result = Struct.new(
      :verdict, :size, :alternate_size, :body, :reasons, :comparisons, :unit,
      keyword_init: true
    )

    def self.recommend(**kwargs)
      new(**kwargs).recommend
    end

    def initialize(chart:, height_cm:, weight_kg:, body_shape: "average", fit_preference: "regular", unit: "cm")
      @chart = chart.deep_stringify_keys
      @height_cm = height_cm.to_f
      @weight_kg = weight_kg.to_f
      @body_shape = BODY_SHAPES.key?(body_shape.to_s) ? body_shape.to_s : "average"
      @fit_preference = FIT_PREFS.key?(fit_preference.to_s) ? fit_preference.to_s : "regular"
      @unit = unit.to_s == "in" ? "in" : "cm"
    end

    def recommend
      rows = Array(@chart["rows"])
      return empty_result if rows.empty? || @height_cm <= 0 || @weight_kg <= 0

      body = estimate_body
      scored = rows.map { |row| score_row(row, body) }.sort_by { |entry| entry[:distance] }
      best = scored.first
      second = scored[1]
      between = second && (second[:distance] - best[:distance]) < 4.0 && best[:distance] > 2.5

      Result.new(
        verdict: between ? "between" : "best",
        size: best[:size],
        alternate_size: between ? second[:size] : nil,
        body: body,
        reasons: best[:reasons],
        comparisons: scored.map { |entry| entry.slice(:size, :distance, :measures) },
        unit: @unit
      )
    end

    private

    def empty_result
      Result.new(
        verdict: "none",
        size: nil,
        alternate_size: nil,
        body: {},
        reasons: [],
        comparisons: [],
        unit: @unit
      )
    end

    def estimate_body
      bmi = @weight_kg / ((@height_cm / 100.0)**2)
      shape = BODY_SHAPES[@body_shape]
      fit_bias = FIT_PREFS[@fit_preference]
      cut_ease = CUT_EASE.fetch(@chart["cut"].to_s, 0.0)
      ease = fit_bias + cut_ease

      # Simple anthropometric estimate: chest ~ half height adjusted by BMI,
      # waist and hips scale from chest. Ease from fit preference and garment cut.
      chest = ((@height_cm * 0.52) + ((bmi - 22) * 1.4)) * shape["chest"] + ease
      waist = (chest * 0.88) * shape["waist"] / shape["chest"] + (ease * 0.7)
      hips = (chest * 0.96) * shape["hips"] / shape["chest"] + (ease * 0.8)
      length = (@height_cm * 0.38) + (ease * 0.2)

      {
        "chest" => chest.round(1),
        "waist" => waist.round(1),
        "hips" => hips.round(1),
        "length" => length.round(1)
      }
    end

    def score_row(row, body)
      garment = @chart["garment"].to_s
      keys = garment == "bottoms" ? %w[waist hips length] : %w[chest waist hips length]
      reasons = []
      total = 0.0
      counted = 0
      measures = {}

      keys.each do |key|
        garment_value = row[key]
        next if garment_value.blank?

        body_value = body[key]
        delta = garment_value.to_f - body_value.to_f
        # Prefer a little ease; punish garments that are tighter than the body.
        distance = delta.negative? ? (delta.abs * 1.6) : (delta * 0.9)
        total += distance
        counted += 1
        measures[key] = { "garment" => garment_value.to_f, "body" => body_value, "delta" => delta.round(1) }
        reasons << {
          "measure" => key,
          "delta" => delta.round(1),
          "note" => reason_note(key, delta)
        }
      end

      {
        size: row["size"],
        distance: counted.zero? ? 999.0 : (total / counted),
        reasons: reasons,
        measures: measures
      }
    end

    def reason_note(measure, delta)
      if delta.abs < 2
        "match"
      elsif delta.negative?
        "snug"
      elsif delta < 6
        "easy"
      else
        "roomy"
      end
    end
  end
end
