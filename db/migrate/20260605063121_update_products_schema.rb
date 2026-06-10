class UpdateProductsSchema < ActiveRecord::Migration[8.1]
  def change
    remove_column :products,
                  :avaliability,
                  :jsonb


    remove_column :products,
                  :price,
                  :decimal


    remove_column :products,
                  :vendor,
                  :string


    remove_column :products,
                  :status,
                  :string


    change_column_null(
      :products,
      :shopify_product_id,
      false
    )


    add_index(
      :products,
      [
        :shop_id,
        :shopify_product_id
      ],
      unique: true,
      name: "index_products_on_shop_and_shopify_id"
    )
  end
end
