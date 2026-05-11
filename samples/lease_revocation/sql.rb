# frozen_string_literal: true

# SQL classifier — sqlglot/pg_query-backed in production.
module SqlClassifier
  StatementClass = Data.define(:op, :tables)

  # Real version: pg_query.parse(sql) walk for tables, dispatch on
  # SelectStmt / InsertStmt / UpdateStmt / DeleteStmt / CreateStmt /
  # DropStmt / AlterTableStmt for op.
  def self.classify(_sql)
    raise NotImplementedError
  end
end
