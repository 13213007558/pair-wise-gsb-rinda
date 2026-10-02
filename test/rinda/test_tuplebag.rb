# frozen_string_literal: false
require 'test/unit'
require 'rinda/tuplespace'

class TestTupleBag < Test::Unit::TestCase

  def setup
    @tb = Rinda::TupleBag.new
  end

  def test_delete
    assert_nothing_raised do
      val = @tb.delete tup(:val, 1)
      assert_equal nil, val
    end

    t = tup(:val, 1)
    @tb.push t

    val = @tb.delete t

    assert_equal t, val

    assert_equal [], @tb.find_all(tem(:val, 1))

    t1 = tup(:val, 1)
    t2 = tup(:val, 1)
    @tb.push t1
    @tb.push t2

    val = @tb.delete t1

    assert_equal t1, val

    assert_equal [t2], @tb.find_all(tem(:val, 1))
  end

  def test_delete_unless_alive
    assert_equal [], @tb.delete_unless_alive

    t1 = tup(:val, nil)
    t2 = tup(:val, nil)

    @tb.push t1
    @tb.push t2

    assert_equal [], @tb.delete_unless_alive

    t1.cancel

    assert_equal [t1], @tb.delete_unless_alive, 'canceled'

    t2.renew Object.new

    assert_equal [t2], @tb.delete_unless_alive, 'expired'
  end

  def test_find
    template = tem(:val, nil)

    assert_equal nil, @tb.find(template)

    t1 = tup(:other, 1)
    @tb.push t1

    assert_equal nil, @tb.find(template)

    t2 = tup(:val, 1)
    @tb.push t2

    assert_equal t2, @tb.find(template)

    t2.cancel

    assert_equal nil, @tb.find(template), 'canceled'

    t3 = tup(:val, 3)
    @tb.push t3

    assert_equal t3, @tb.find(template)

    t3.renew Object.new

    assert_equal nil, @tb.find(template), 'expired'
  end

  def test_find_all
    template = tem(:val, nil)

    t1 = tup(:other, 1)
    @tb.push t1

    assert_equal [], @tb.find_all(template)

    t2 = tup(:val, 2)
    t3 = tup(:val, 3)

    @tb.push t2
    @tb.push t3

    assert_equal [t2, t3], @tb.find_all(template)

    t2.cancel

    assert_equal [t3], @tb.find_all(template), 'canceled'

    t3.renew Object.new

    assert_equal [], @tb.find_all(template), 'expired'
  end

  def test_find_all_template
    tuple = tup(:val, 1)

    t1 = tem(:other, nil)
    @tb.push t1

    assert_equal [], @tb.find_all_template(tuple)

    t2 = tem(:val, nil)
    t3 = tem(:val, nil)

    @tb.push t2
    @tb.push t3

    assert_equal [t2, t3], @tb.find_all_template(tuple)

    t2.cancel

    assert_equal [t3], @tb.find_all_template(tuple), 'canceled'

    t3.renew Object.new

    assert_equal [], @tb.find_all_template(tuple), 'expired'
  end

  def test_find_matching_all
    t1 = tup(:val, 1)
    t2 = tup(:val, 2)
    @tb.push(t1)
    @tb.push(t2)

    entries = @tb.find_matching_all([tem(:val, 1), tem(:val, nil)])

    assert_equal([t1, t2], entries)
    assert_equal(2, entries.map(&:object_id).uniq.size)
  end

  def test_find_matching_all_duplicate_tuples
    t1 = tup(:same)
    t2 = tup(:same)
    @tb.push(t1)
    @tb.push(t2)

    entries = @tb.find_matching_all([tem(nil), tem(nil)])

    assert_equal([t1, t2], entries)
    assert_equal(2, entries.map(&:object_id).uniq.size)
  end

  def test_find_matching_all_exhaustive
    entries = 3.times.map { |i| tup(i) }
    entries.each { |entry| @tb.push(entry) }

    (0...(1 << 9)).each do |mask|
      templates = 3.times.map do |row|
        allowed = 3.times.filter_map do |column|
          column if mask[row * 3 + column] == 1
        end
        tem(->(value) { allowed.include?(value) })
      end

      expected = (0...3).to_a.permutation.any? do |mapping|
        mapping.each_with_index.all? do |tuple_index, template_index|
          mask[template_index * 3 + tuple_index] == 1
        end
      end

      actual = @tb.find_matching_all(templates)

      if expected
        assert_equal(3, actual.map(&:object_id).uniq.size)
        actual.each_with_index do |entry, template_index|
          assert(entries.include?(entry))
          assert(templates[template_index].match(entry))
        end
      else
        assert_nil(actual)
      end
    end
  end

  def test_find_matching_all_without_templates
    assert_equal([], @tb.find_matching_all([]))
  end

  def test_has_expires_eh
    assert !@tb.has_expires?

    t = tup(:val, 1)
    @tb.push t

    assert @tb.has_expires?

    t.renew Object.new

    assert !@tb.has_expires?
  end

  def test_push
    t = tup(:val, 1)

    @tb.push t

    assert_equal t, @tb.find(tem(:val, 1))
  end

  ##
  # Create a tuple with +ary+ for its contents

  def tup(*ary)
    Rinda::TupleEntry.new ary
  end

  ##
  # Create a template with +ary+ for its contents

  def tem(*ary)
    Rinda::TemplateEntry.new ary
  end

end
