require 'rubygems'
require 'sequel'

DB = Sequel.sqlite('db/quoted_links.sqlite')
class QuotedLink < Sequel::Model
end