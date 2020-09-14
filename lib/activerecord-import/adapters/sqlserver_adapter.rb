module ActiveRecord::Import::SQLServerAdapter
  include ActiveRecord::Import::ImportSupport

  def supports_on_duplicate_key_update?
    false
  end

  def insert_many( sql, values, options = {}, name = 'Import', *args )
    base_sql, post_sql = if sql.is_a?( String )
      [sql, '']
    elsif sql.is_a?( Array )
      [sql.shift, sql.join( ' ' )]
    end

    columns_names = base_sql.match(/INSERT INTO (\[.*\]) (\(.*\)) VALUES /)[2][1..-1].split(',')
    sql_id_index  = columns_names.index('[id]')
    sql_noid      = if sql_id_index.nil?
      nil
    else
      (sql_id_index == (columns_names.length - 1) ? base_sql.clone.gsub(/\[id\]/, '') : base_sql.clone.gsub(/\[id\],/, ''))
    end

    max = max_allowed_packet

    table_name = get_table_name(base_sql)
    id_column = primary_key(table_name)

    number_of_inserts = 0
    results = []
    while !(batch = values.shift(max)).blank? do
      if sql_id_index
        null_ids     = []
        supplied_ids = []

        batch.each do |value|
          values_sql = value[1..-2].split(',')
          if values_sql[sql_id_index] == "NULL"
            values_sql.delete_at(sql_id_index)
            null_ids << "(#{values_sql.join(',')})"
          else
            supplied_ids << value
          end
        end

        unless null_ids.empty?
          number_of_inserts += 1
          sql2insert = sql_noid + null_ids.join( ',' ) + post_sql
          results.push(*exec_insert( sql2insert, args.first, [], id_column ).rows.flatten)
        end
        unless supplied_ids.empty?
          number_of_inserts += 1
          sql2insert = base_sql + supplied_ids.join( ',' ) + post_sql
          results.push(*exec_insert( sql2insert, args.first, [], id_column ).rows.flatten)
        end
      else
        number_of_inserts += 1
        sql2insert = base_sql + batch.join( ',' ) + post_sql
        results.push(*exec_insert( sql2insert, args.first, [], id_column ).rows.flatten)
      end
    end

    ActiveRecord::Import::Result.new([], number_of_inserts, results, [])
  end

  def max_allowed_packet
    1000
  end
end
