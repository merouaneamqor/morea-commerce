class CollectionProduct < ApplicationRecord
  belongs_to :collection
  belongs_to :product

  validates :product_id, uniqueness: { scope: :collection_id }
end
