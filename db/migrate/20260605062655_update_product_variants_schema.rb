class UpdateProductVariantsSchema < ActiveRecord::Migration[8.1]
  def change
    remove_column :product_variants,
                  :inventory_policy,
                  :string


    change_column_default(
      :product_variants,
      :available,
      true
    )


    change_column_default(
      :product_variants,
      :inventory_quantity,
      0
    )


    change_column_default(
      :product_variants,
      :options,
      {}
    )


    change_column_null(
      :product_variants,
      :options,
      false
    )


    add_index(
      :product_variants,
      [
        :shop_id,
        :shopify_variant_id
      ],
      unique: true
    )
  end
end
