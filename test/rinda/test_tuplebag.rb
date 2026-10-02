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

  def test_find_all_match
    assert_equal [], @tb.find_all_match([])

    t1 = tup(:val, 1)
    t2 = tup(:val, 2)
    @tb.push t1
    @tb.push t2

    assert_equal [t1], @tb.find_all_match([tem(:val, 1)])
    assert_equal [t1, t2], @tb.find_all_match([tem(:val, 1), tem(:val, 2)])

    # two templates need two distinct tuples
    assert_equal nil, @tb.find_all_match([tem(:val, 1), tem(:val, 1)])

    matched = @tb.find_all_match([tem(:val, nil), tem(:val, nil)])
    assert_equal 2, matched.size
    assert_equal [t1, t2].sort_by(&:object_id), matched.sort_by(&:object_id)

    # overlapping templates: greedy assignment in template order would
    # pick u1 for the first template and get stuck
    tb2 = Rinda::TupleBag.new
    u1 = tup(:b)
    u2 = tup(:a)
    tb2.push u1
    tb2.push u2
    assert_equal [u2, u1], tb2.find_all_match([tem(nil), tem(:b)])

    # dead tuples are not matched
    t1.cancel
    assert_equal nil, @tb.find_all_match([tem(:val, nil), tem(:val, nil)])
    assert_equal [t2], @tb.find_all_match([tem(:val, nil)])
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
