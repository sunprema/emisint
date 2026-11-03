defmodule Emisint.Improvement.DisplayTest do
  use ExUnit.Case, async: true

  alias Emisint.Improvement.Display
  alias Emisint.Improvement.Seeds.FortYates

  describe "goal_description/1" do
    test "corrects the Goal 3 typos for display; the imported wording is kept" do
      stored = Enum.find(FortYates.goals(), &(&1.number == 3)).description

      # The seed keeps the workbook's wording (Ft Yates Goals!B18).
      assert stored =~ "perfoming"
      assert stored =~ "data-drive practices"

      shown = Display.goal_description(stored)

      assert shown =~ "students performing at the novice level"
      assert shown =~ "data-driven practices"
      refute shown =~ "perfoming"
      refute shown =~ "data-drive practices"
    end

    test "leaves other text and nil unchanged" do
      assert Display.goal_description(nil) == nil
      assert Display.goal_description("data-driven practices") == "data-driven practices"
    end
  end
end
