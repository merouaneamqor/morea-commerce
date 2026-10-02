# frozen_string_literal: true

# Manual ordering within a scope (home sections, menu items); new records go last
module Positioned
  extend ActiveSupport::Concern

  included do
    before_create :assign_last_position
  end

  def move!(direction)
    siblings = position_scope.ordered.to_a
    from = siblings.index(self)
    to = direction.to_s == "up" ? from - 1 : from + 1
    return false if from.nil? || to.negative? || to >= siblings.size

    siblings[from], siblings[to] = siblings[to], siblings[from]
    self.class.transaction do
      siblings.each_with_index { |record, index| record.update_column(:position, index) }
    end
    true
  end

  private

  def assign_last_position
    self.position = (position_scope.maximum(:position) || -1) + 1 if position.to_i.zero? && position_scope.exists?
  end
end
