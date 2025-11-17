class CreateProperties < ActiveRecord::Migration[7.1]
  def change
    create_table :properties do |t|
      t.string :name
      t.string :address
      t.references :user, null: false, foreign_key: true
      t.string :jurisdiction

      t.timestamps
    end
  end
end
