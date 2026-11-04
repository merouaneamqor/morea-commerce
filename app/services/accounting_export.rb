# frozen_string_literal: true

require "csv"

# The accounting export: one row per delivered order, per returned order and per day of ad spend, then the totals.
# It reads the lines of AccountingStats (the same ones the cards are built from) and adds them up on its own, so the
# totals row is always the sum of the rows above it, and equal to what the cards show.
class AccountingExport
  HEADER = %w[date type order revenue cost_of_goods delivery_fees advertising].freeze
  KINDS = { "delivered" => "livraison", "returned" => "retour", "ads" => "publicite" }.freeze

  def initialize(stats)
    @stats = stats
  end

  def lines
    @lines ||= @stats.lines.sort_by { |line| [ line.date, KINDS.keys.index(line.kind), line.number.to_s ] }
  end

  # [revenue, cost of goods, delivery fees, advertising] in centimes, summed from the rows.
  def totals
    [ lines.sum(&:revenue), lines.sum(&:goods), lines.sum(&:delivery), lines.sum(&:ads) ]
  end

  def filename
    "comptabilite-#{@stats.month.strftime("%Y-%m")}-#{@stats.basis}.csv"
  end

  def to_csv
    revenue, goods, delivery, ads = totals
    expenses = goods + delivery + ads
    "﻿" + CSV.generate do |csv|
      csv << HEADER
      lines.each do |line|
        csv << [ line.date.iso8601, KINDS.fetch(line.kind), line.number, money(line.revenue), money(line.goods), money(line.delivery), money(line.ads) ]
      end
      csv << [ "TOTAL", "", lines.count { |line| line.kind == "delivered" }, money(revenue), money(goods), money(delivery), money(ads) ]
      csv << [ "MARGE_BRUTE", "", "", money(revenue - goods), "", "", "" ]
      csv << [ "TOTAL_DEPENSES", "", "", "", "", "", money(expenses) ]
      csv << [ "BENEFICE_NET", "", "", money(revenue - expenses), "", "", "" ]
    end
  end

  private

  # Whole centimes as "123.45", with integer arithmetic only.
  def money(cents)
    sign = cents.negative? ? "-" : ""
    "#{sign}#{cents.abs / 100}.#{format("%02d", cents.abs % 100)}"
  end
end
