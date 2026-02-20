# frozen_string_literal: true

# Example: Ruby control flow + LLM decisions
require "mana"

player_hp = 100
enemy_hp = 80
inventory = ["sword", "potion", "shield", "herb"]

round = 0
while player_hp > 0 && enemy_hp > 0
  round += 1
  puts "=== Round #{round} | Player: #{player_hp} HP | Enemy: #{enemy_hp} HP ==="

  ~"玩家 HP=<player_hp>，敌人 HP=<enemy_hp>，背包=<inventory>。选行动存 <action>（attack/defend/use_item），如果 use_item 把物品名存 <item_name>"

  case action
  when "attack"
    damage = rand(15..25)
    enemy_hp -= damage
    puts "Attack! #{damage} damage"
  when "defend"
    puts "Defending..."
  when "use_item"
    if inventory.include?(item_name)
      inventory.delete(item_name)
      player_hp += 25 if %w[potion herb].include?(item_name)
      puts "Used #{item_name}!"
    end
  end

  player_hp -= action == "defend" ? rand(5..10) : rand(10..20)
end

puts player_hp > 0 ? "Victory!" : "Defeat..."
