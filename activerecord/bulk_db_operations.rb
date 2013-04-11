# Add "bulk insert" capability to ActiveRecord, to speed up operations involving a lot of records

# This was designed to work with AR 3.2.12 --  your mileage may vary with higher or lower versions
# Put it in config/initializers

# First, we need to add some new features to Arel, the SQL generation layer used by Active Record

Arel::Visitors::ToSql.class_eval do

  # Arel's implementation of INSERT statements ONLY handles the case where a single record is being inserted
  # We'll extend it to handle multiple records
  # I don't want to mess around with the internals of the Arel::Nodes::InsertStatement class,
  #   because it's used in a lot of places and we could easily break something
  # Instead, we'll say that if the number of values for an InsertStatement is 2x or more the number
  #   of columns, that means multiple records should be inserted
  # None of the existing code which uses InsertStatement in ActiveRecord, etc. ever does that,
  #   so the behavior of all existing code should be unchanged

  def visit_Arel_Nodes_Values o
    records = o.expressions.each_slice(o.columns.length)

    "VALUES " + records.map do |record|
      "(#{record.zip(o.columns).map { |value, attr|
        if Arel::Nodes::SqlLiteral === value
          visit value
        else
          quote(value, attr && column_for(attr))
        end
      }.join ', '})"
    end.join(', ')
  end
end

Arel::InsertManager.class_eval do
  def columns= cols; @ast.columns = cols; end
end

# OK, that's pretty cool. Now our interface for bulk inserts will look like this:
#
#   [a, b, c].bulk_create
#
# ...where +a+, +b+, and +c+ are assumed to be new ActiveRecord::Base objects of the same class
#
# It would be nicer to have #bulk_save and #bulk_save!, which would work on both new or already-saved
# AR::Base objects, of any class, in any combination, but that will have to wait for another day

module Enumerable
  def bulk_create
    return if empty?

    # Chew out callers who give us invalid input
    raise "No, no! You are very bad!" unless all?(&:new_record?) && all? { |record| record.class == first.class }

    values  = []
    columns = nil
    each do |record|
      attrs = record.send(:arel_attributes_values, false).to_a
      attrs.sort_by! { |k,_| k.name }
      columns = attrs.map(&:first) if columns.nil?
      values.concat(attrs.map { |_,v| v })
    end

    table = first.class.arel_table
    insert = Arel::InsertManager.new(ActiveRecord::Base)
    insert.into(table)
    insert.columns = columns
    insert.values = insert.create_values(values, columns)
    insert.ast.relation = columns.first.relation

    ActiveRecord::Base.connection.execute(insert.to_sql)
    true
  end
end