#!/usr/bin/env python3
"""Generate ONLY the main content sections from content.json.
Template handles everything else (CSS, sidebar, footer, JS)."""
import json, sys, os

def esc(s):
    return (s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')

def generate_hero(hero):
    h = hero or {}
    title = esc(h.get('title', 'Corrupted SMP Wiki'))
    subtitle = esc(h.get('subtitle', ''))
    banner = esc(h.get('banner', 'smp_banner.jpg'))
    banner_w = h.get('banner_width', 120)
    banner_h = h.get('banner_height', 120)

    stats = h.get('stats', [])
    if not stats:
        stats = [
            {'value': 6, 'label': 'Ranks'},
            {'value': 7, 'label': 'Custom Weapons'},
            {'value': 5, 'label': 'Crates'},
            {'value': 8, 'label': 'Custom Items'}
        ]

    stats_html = ''
    for s in stats:
        v = s.get('value', 0)
        l = esc(s.get('label', ''))
        stats_html += f'<div class="hero-stat"><span class="value hero-stat-num" data-target="{v}">0<span class="plus">+</span></span><span class="label">{l}</span></div>'

    particles = ''
    delays = [0, 0.4, 0.8, 1.2, 1.6]
    positions = [(20,15), (60,80), (40,50), (75,25), (30,70)]
    for i, (top, left) in enumerate(positions):
        particles += f'<div class="hero-particle" style="top:{top}%;left:{left}%;animation-delay:{delays[i]}s"></div>'

    return f'''      <section class="hero fade-in" id="home">
        {particles}
        <div class="hero-content">
          <img src="images/{banner}" alt="Corrupted SMP" style="width:{banner_w}px;height:{banner_h}px;border-radius:16px;margin:0 auto 1.5rem;display:block;border:2px solid var(--purple-border);box-shadow:0 0 30px rgba(147,51,234,0.3);object-fit:cover;">
          <h1>{title}</h1>
          <p>{subtitle}</p>
          <div class="hero-stats">
            {stats_html}
          </div>
        </div>
      </section>'''

def generate_ranks(ranks_data):
    r = ranks_data or {}
    desc = r.get('description', '')
    subscription = r.get('subscription_ranks', [])
    special = r.get('special_ranks', [])

    def rank_card(rank):
        name = rank.get('name', '')
        color = rank.get('color', '#9333ea')
        color_class = rank.get('color_class', '')
        badge = rank.get('badge', '')
        price = rank.get('price', '')
        description = rank.get('description', '')
        perks = rank.get('perks', [])
        commands = rank.get('commands', [])

        if color_class:
            badge_html = f'<div class="card-rank {color_class}">{badge} {name}</div>'
        else:
            badge_html = f'<div class="card-rank" style="color:{color}">{badge} {name}</div>'

        perks_html = ''.join(f'<li>{p}</li>' for p in perks)
        cmds_html = ''
        if commands:
            cmd_spans = ' '.join(f'<span class="inline-code">{esc(c)}</span>' for c in commands)
            cmds_html = f'<div class="commands-section"><div style="font-size:0.75rem;font-weight:700;text-transform:uppercase;letter-spacing:0.05em;color:var(--text-muted);margin-bottom:0.5rem;">Commands</div><div>{cmd_spans}</div></div>'

        price_html = "<div class=\"price\">" + price + "</div>" if price else ""
        perks_block = "<ul class=\"perks-list\">" + perks_html + "</ul>" if perks else ""
        return f'''      <div class="card">
        {badge_html}
        <h3>{name}</h3>
        {price_html}
        <p>{description}</p>
        {perks_block}
        {cmds_html}
      </div>'''

    sub_html = ''.join(rank_card(r) for r in subscription)
    spec_html = ''.join(rank_card(r) for r in special)

    return f'''      <section class="section fade-in" id="ranks">
        <div class="section-header"><div class="section-icon">👑</div><h2>Ranks</h2></div>
        <p class="section-desc">{desc}</p>
        <div class="tabs">
          <button class="tab-btn active" onclick="switchTab(event,'tab-subscription')">Subscription Ranks</button>
          <button class="tab-btn" onclick="switchTab(event,'tab-special')">Special Ranks</button>
        </div>
        <div class="tab-content active" id="tab-subscription">
          <div class="card-grid">
      {sub_html}
          </div>
        </div>
        <div class="tab-content" id="tab-special">
          <div class="card-grid">
      {spec_html}
          </div>
        </div>
      </section>'''

def generate_weapons(weapons_data):
    w = weapons_data or {}
    desc = w.get('description', '')
    weapons = w.get('weapons', [])
    cards = ''

    for wep in weapons:
        name = esc(wep.get('name', ''))
        badge = esc(wep.get('badge', ''))
        description = esc(wep.get('description', ''))
        crafting = wep.get('crafting', None)
        abilities = wep.get('abilities', [])
        info = wep.get('info', None)
        warning = wep.get('warning', None)

        if badge:
            header = f'''        <div class="weapon-header">
          <h3>{name}</h3>
          <span class="weapon-type-badge">{badge}</span>
        </div>'''
        else:
            header = f'''        <div class="weapon-header">
          <h3>{name}</h3>
        </div>'''

        craft_html = ''
        if crafting and crafting.get('grid'):
            grid = crafting.get('grid', [''] * 9)
            if any(grid):
                result_name = esc(crafting.get('result_name', ''))
                result_icon = esc(crafting.get('result_icon', ''))
                slots = ''.join(
                    f'<div class="craft-slot"><img src="images/{esc(s)}.png" class="item-icon" alt="{esc(s)}" title="{esc(s)}" onerror="imgErr(this)"></div>' if s else '<div class="craft-slot empty"></div>'
                    for s in grid
                )
                craft_html = f'''
        <div class="crafting-section"><div class="crafting-title">Crafting Recipe</div><div class="crafting-recipe-wrap"><div class="crafting-grid">{slots}</div><div class="craft-arrow">→</div><div class="craft-result"><div class="craft-result-slot"><img src="images/{result_icon}.png" class="item-icon" alt="{result_name}" title="{result_name}" onerror="imgErr(this)"></div><div class="craft-result-name">{result_name}</div></div></div></div>'''

        info_html = ''
        if info:
            info_html = f'''
        <div class="info-box"><h4>📦 Obtainment</h4><p>{esc(info)}</p></div>'''
        if warning:
            info_html = f'''
        <div class="info-box warning"><h4>⚠ Limited Edition</h4><p>{esc(warning)}</p></div>'''

        abilities_html = ''
        if abilities:
            ability_items = ''.join(
                f'<div class="ability"><div class="ability-name">{esc(a.get("name", ""))}</div><div class="ability-desc">{a.get("description", "")}</div></div>'
                for a in abilities
            )
            abilities_html = f'''
        <div class="abilities-grid">{ability_items}</div>'''

        cards += f'''
      <div class="weapon-card fade-in" id="">
{header}
        <p>{description}</p>{craft_html}{info_html}{abilities_html}
      </div>'''

    search_bar = '''
      <div class="search-bar fade-in">
        <span class="search-icon">🔍</span>
        <input type="text" id="searchInput" placeholder="Search wiki — ranks, weapons, crates, items..." oninput="filterContent(this.value)">
      </div>'''

    return f'''
      <section class="section fade-in" id="weapons">
        <div class="section-header"><div class="section-icon">⚔️</div><h2>Custom Weapons</h2></div>
        <p class="section-desc">{desc}</p>
{cards}
      </section>'''

def generate_crates(crates_data):
    c = crates_data or {}
    desc = c.get('description', '')
    info = esc(c.get('info', ''))
    crates_list = c.get('crates', [])

    info_html = f'''
        <div class="info-box"><h4>🔑 How to Earn Keys</h4><p>{info}</p></div>''' if info else ''
    cards = ''

    for crate in crates_list:
        name = esc(crate.get('name', ''))
        price = esc(crate.get('price', ''))
        description = esc(crate.get('description', ''))
        rewards = crate.get('rewards', [])

        price_html = f'<div class="price">{price}</div>' if price else ''
        rewards_html = ''
        if rewards:
            tags = ''.join(
                f'<span class="reward-tag{" rare" if r.get("rare") else ""}">{esc(r.get("name", ""))}</span>'
                for r in rewards
            )
            rewards_html = f'''
        <div class="rewards-grid">{tags}</div>'''

        cards += f'''
      <div class="crate-card fade-in" id="">
        <div class="crate-header"><h3>{name}</h3></div>
        {price_html}
        <p>{description}</p>{rewards_html}
      </div>'''

    return f'''
      <section class="section fade-in" id="crates">
        <div class="section-header"><div class="section-icon">📦</div><h2>Crates</h2></div>
        <p class="section-desc">{desc}</p>{info_html}
{cards}
      </section>'''

def generate_items(items_data):
    it = items_data or {}
    desc = esc(it.get('description', ''))
    items_list = it.get('items', [])
    cards = ''

    for item in items_list:
        name = esc(item.get('name', ''))
        badge = esc(item.get('badge', ''))
        description = esc(item.get('description', ''))
        crafting = item.get('crafting', None)
        abilities = item.get('abilities', [])
        info = item.get('info', None)

        if badge:
            header = f'''        <div class="item-header">
          <h3>{name}</h3>
          <span class="weapon-type-badge">{badge}</span>
        </div>'''
        else:
            header = f'''        <div class="item-header">
          <h3>{name}</h3>
        </div>'''

        craft_html = ''
        if crafting and crafting.get('grid'):
            grid = crafting.get('grid', [''] * 9)
            if any(grid):
                result_name = esc(crafting.get('result_name', ''))
                result_icon = esc(crafting.get('result_icon', ''))
                slots = ''.join(
                    f'<div class="craft-slot"><img src="images/{esc(s)}.png" class="item-icon" alt="{esc(s)}" title="{esc(s)}" onerror="imgErr(this)"></div>' if s else '<div class="craft-slot empty"></div>'
                    for s in grid
                )
                craft_html = f'''
        <div class="crafting-section"><div class="crafting-title">Crafting Recipe</div><div class="crafting-recipe-wrap"><div class="crafting-grid">{slots}</div><div class="craft-arrow">→</div><div class="craft-result"><div class="craft-result-slot"><img src="images/{result_icon}.png" class="item-icon" alt="{result_name}" title="{result_name}" onerror="imgErr(this)"></div><div class="craft-result-name">{result_name}</div></div></div></div>'''

        info_html = ''
        if info:
            info_html = f'''
        <div class="info-box"><h4>📦 Obtainment</h4><p>{esc(info)}</p></div>'''

        abilities_html = ''
        if abilities:
            ability_items = ''.join(
                f'<div class="ability"><div class="ability-name">{esc(a.get("name", ""))}</div><div class="ability-desc">{a.get("description", "")}</div></div>'
                for a in abilities
            )
            abilities_html = f'''
        <div class="abilities-grid">{ability_items}</div>'''

        cards += f'''
      <div class="item-card fade-in" id="">
{header}
        <p>{description}</p>{craft_html}{info_html}{abilities_html}
      </div>'''

    return f'''
      <section class="section fade-in" id="items">
        <div class="section-header"><div class="section-icon">🔮</div><h2>Custom Items</h2></div>
        <p class="section-desc">{desc}</p>
{cards}
      </section>'''

def generate_systems(systems_data):
    s = systems_data or {}
    desc = esc(s.get('description', ''))
    cards_list = s.get('cards', [])
    cards = ''
    for card in cards_list:
        name = esc(card.get('name', ''))
        icon = card.get('icon', '')
        color_class = card.get('color_class', '')
        description = esc(card.get('description', ''))
        cards += f'''
        <div class="card"><div class="card-rank {color_class}">{icon} {name}</div><p style="margin-top:0.5rem;color:var(--text-secondary);line-height:1.7;">{description}</p></div>'''

    return f'''
      <section class="section fade-in" id="systems">
        <div class="section-header"><div class="section-icon">⚙️</div><h2>Systems Overview</h2></div>
        <p class="section-desc">{desc}</p>
        <div class="card-grid" style="grid-template-columns:repeat(auto-fill,minmax(260px,1fr));">{cards}
        </div>
      </section>'''

def generate(content):
    hero = generate_hero(content.get('hero'))
    ranks = generate_ranks(content.get('ranks'))
    weapons = generate_weapons(content.get('weapons'))
    crates = generate_crates(content.get('crates'))
    items = generate_items(content.get('items'))
    systems = generate_systems(content.get('systems'))

    search_bar = '''
      <div class="search-bar fade-in">
        <span class="search-icon">🔍</span>
        <input type="text" id="searchInput" placeholder="Search wiki — ranks, weapons, crates, items..." oninput="filterContent(this.value)">
      </div>'''

    return f'''
    <main class="main-content">
{hero}
{search_bar}
{ranks}
{weapons}
{crates}
{items}
{systems}
    </main>
  </div>'''

if __name__ == '__main__':
    content_file = sys.argv[1] if len(sys.argv) > 1 else 'content.json'
    template_file = sys.argv[2] if len(sys.argv) > 2 else 'wiki-template.html'
    output_file = sys.argv[3] if len(sys.argv) > 3 else 'public/index.html'

    with open(content_file) as f:
        content = json.load(f)

    with open(template_file) as f:
        template = f.read()

    body = generate(content)
    html = template.replace('<!--WIKI_BODY-->', body)

    os.makedirs(os.path.dirname(output_file) or '.', exist_ok=True)
    with open(output_file, 'w') as f:
        f.write(html)

    print(f'Generated {output_file} ({len(html):,} bytes)')
