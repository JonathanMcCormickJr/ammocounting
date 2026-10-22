require "test_helper"

class PriceIndexTest < ActiveSupport::TestCase
  test "build returns the mock by default" do
    assert_instance_of PriceIndex::Mock, PriceIndex.build
  end

  test "build accepts string names" do
    assert_instance_of PriceIndex::Mock, PriceIndex.build("mock")
  end

  test "build rejects unknown index" do
    assert_raises(ArgumentError) { PriceIndex.build(:bogus) }
  end
end
