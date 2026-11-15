# frozen_string_literal: true

module Storefront
  # Estimates body measurements from height/weight/shape, adds garment ease from
  # cut + fit preference, then picks the closest finished size on the chart.
  # Charts store garment centimetres (not body). Kept in Ruby so scoring can be
  # tested; the Stimulus controller mirrors the same rules client-side.
  class SizeAdvisor
    BODY_SHAPES = {
      "slim" => { "chest" => 0.95, "waist" => 0.91, "hips" => 0.96 },
      "average" => { "chest" => 1.0, "waist" => 1.0, "hips" => 1.0 },
      "athletic" => { "chest" => 1.04, "waist" => 0.93, "hips" => 1.01 },
      "broad" => { "chest" => 1.06, "waist" => 1.06, "hips" => 1.04 }
    }.freeze

    # Profile-aware anthropometrics. Chest grows with height and softened BMI;
    # waist/hips scale from the same base with different ratios per profile.
    PROFILES = {
      "menswear" => {
        "chest_h" => 0.50, "chest_bmi" => 1.9, "chest_base" => 6.0,
        "waist_r" => 0.86, "hips_r" => 0.97, "length_r" => 0.40, "waist_bmi" => 0.85
      },
      "womenswear" => {
        "chest_h" => 0.48, "chest_bmi" => 1.45, "chest_base" => 3.5,
        "waist_r" => 0.77, "hips_r" => 1.07, "length_r" => 0.37, "waist_bmi" => 0.75
      },
      "unisex" => {
        "chest_h" => 0.49, "chest_bmi" => 1.7, "chest_base" => 4.8,
        "waist_r" => 0.82, "hips_r" => 1.02, "length_r" => 0.385, "waist_bmi" => 0.8
      }
    }.freeze

    # Finished-garment ease (cm) on top of body — charts are garment measures.
    BASE_EASE = {
      "tops" => { "chest" => 10.0, "waist" => 11.0, "hips" => 8.0, "length" => 0.0 },
      "bottoms" => { "chest" => 0.0, "waist" => 3.0, "hips" => 5.0, "length" => 0.0 }
    }.freeze

    FIT_PREFS = {
      "fitted" => -3.0,
      "regular" => 0.0,
      "relaxed" => 5.0
    }.freeze

    CUT_EASE = {
      "slim" => -3.0,
      "regular" => 0.0,
      "relaxed" => 3.0,
      "oversized" => 8.0
    }.freeze

    MEASURE_WEIGHTS = {
      "tops" => { "chest" => 1.0, "waist" => 0.5, "hips" => 0.4, "length" => 0.25 },
      "bottoms" => { "chest" => 0.0, "waist" => 1.0, "hips" => 0.95, "length" => 0.2 }
    }.freeze

    BETWEEN_GAP = 3.5
    BETWEEN_MIN_BEST = 1.8

    Result = Struct.new(
      :verdict, :size, :alternate_size, :body, :target, :reasons, :comparisons, :unit,
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
      @profile = PROFILES.key?(@chart["profile"].to_s) ? @chart["profile"].to_s : "unisex"
      @garment = BASE_EASE.key?(@chart["garment"].to_s) ? @chart["garment"].to_s : "tops"
      @cut = CUT_EASE.key?(@chart["cut"].to_s) ? @chart["cut"].to_s : "regular"
    end

    def recommend
      rows = Array(@chart["rows"])
      return empty_result if rows.empty? || @height_cm <= 0 || @weight_kg <= 0

      body = estimate_body
      target = garment_target(body)
      scored = rows.map { |row| score_row(row, target) }.sort_by { |entry| entry[:distance] }
      best = scored.first
      second = scored[1]
      between = second && (second[:distance] - best[:distance]) < BETWEEN_GAP && best[:distance] > BETWEEN_MIN_BEST

      Result.new(
        verdict: between ? "between" : "best",
        size: best[:size],
        alternate_size: between ? second[:size] : nil,
        body: body,
        target: target,
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
        target: {},
        reasons: [],
        comparisons: [],
        unit: @unit
      )
    end

    def estimate_body
      profile = PROFILES[@profile]
      shape = BODY_SHAPES[@body_shape]
      bmi = (@weight_kg / ((@height_cm / 100.0)**2)).clamp(17.0, 40.0)
      bmi_delta = bmi - 22.0
      # Soften high BMI so weight alone does not skip two sizes.
      soft_bmi = bmi_delta >= 0 ? (bmi_delta**0.92) : bmi_delta

      chest = (
        (@height_cm * profile["chest_h"]) +
        (soft_bmi * profile["chest_bmi"]) +
        profile["chest_base"]
      ) * shape["chest"]

      waist = (
        (@height_cm * profile["chest_h"] * profile["waist_r"]) +
        (soft_bmi * (profile["chest_bmi"] * profile["waist_r"] + profile["waist_bmi"])) +
        (profile["chest_base"] * profile["waist_r"])
      ) * shape["waist"]

      hips = (
        (@height_cm * profile["chest_h"] * profile["hips_r"]) +
        (soft_bmi * profile["chest_bmi"] * profile["hips_r"]) +
        (profile["chest_base"] * profile["hips_r"])
      ) * shape["hips"]

      length = @height_cm * profile["length_r"]

      {
        "chest" => chest.round(1),
        "waist" => waist.round(1),
        "hips" => hips.round(1),
        "length" => length.round(1)
      }
    end

    def garment_target(body)
      base = BASE_EASE[@garment]
      ease = FIT_PREFS[@fit_preference] + CUT_EASE[@cut]

      body.keys.each_with_object({}) do |key, memo|
        measure_ease = key == "length" ? (ease * 0.2) : ease
        memo[key] = (body[key] + base.fetch(key, 0.0) + measure_ease).round(1)
      end
    end

    def score_row(row, target)
      keys = @garment == "bottoms" ? %w[waist hips length] : %w[chest waist hips length]
      weights = MEASURE_WEIGHTS[@garment]
      reasons = []
      total = 0.0
      weight_sum = 0.0
      measures = {}

      keys.each do |key|
        garment_value = row[key]
        next if garment_value.blank?

        weight = weights.fetch(key, 0.0)
        next if weight <= 0

        body_or_target = target[key]
        delta = garment_value.to_f - body_or_target.to_f
        distance = measure_distance(key, delta)
        total += distance * weight
        weight_sum += weight
        measures[key] = { "garment" => garment_value.to_f, "target" => body_or_target, "delta" => delta.round(1) }
        reasons << {
          "measure" => key,
          "delta" => delta.round(1),
          "note" => reason_note(key, delta)
        }
      end

      {
        size: row["size"],
        distance: weight_sum.zero? ? 999.0 : (total / weight_sum),
        reasons: reasons,
        measures: measures
      }
    end

    def measure_distance(measure, delta)
      if measure == "length"
        delta.negative? ? (delta.abs * 1.4) : (delta * 0.6)
      else
        delta.negative? ? (delta.abs * 1.65) : (delta * 0.85)
      end
    end

    def reason_note(measure, delta)
      threshold = measure == "length" ? 2.5 : 2.0
      if delta.abs < threshold
        "match"
      elsif delta.negative?
        "snug"
      elsif delta < 7
        "easy"
      else
        "roomy"
      end
    end
  end
end
