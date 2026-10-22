class AddCostBasisMethodToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :cost_basis_method, :string, null: false, default: "weighted_average"
  end
end
