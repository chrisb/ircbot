require 'rubygems'
require 'sequel'

module Database
  def self.create(db_name='database.sqlite')
    db = Sequel.sqlite(db_name)
    db.create_table :quoted_links do
      primary_key :id
      column :username, :text
      column :hostname, :text
      column :url, :text
      column :context, :text
      column :local_mirror, :text
      column :created_at, :datetime
    end
  end
end