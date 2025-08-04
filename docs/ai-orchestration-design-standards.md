# AI Orchestration Design Standards for OverSkill

**Last Updated**: August 4, 2025  
**Status**: Production Ready  
**Location**: `/docs/ai-orchestration-design-standards.md`

## Overview

This document defines the enhanced AI orchestration approach that enables OverSkill to generate Base44-level sophisticated applications while maintaining our file-based deployment constraints.

## Key Philosophy: Design-First vs Constraint-First

### ❌ Previous Approach (Constraint-First)
- Led with technical restrictions
- Focused on what's forbidden
- Created functional but bland applications
- Patched existing features incrementally

### ✅ Current Approach (Design-First)
- Leads with design excellence requirements
- Emphasizes professional polish and "wow" factor
- Creates complete, sophisticated systems
- Plans holistic user experiences

## Enhanced Prompt Structure

### 1. Analysis Prompt (`build_analysis_prompt`)

**Location**: `app/services/ai/open_router_client.rb:189`

**Key Enhancements**:
```ruby
DESIGN EXCELLENCE REQUIREMENTS:
- Create sophisticated, professional-grade applications that truly WOW users
- Choose sophisticated color palettes with specific hex codes
- Plan typography hierarchy for readability and elegance
- Leverage Shadcn/ui components for professional interfaces
- Consider industry-specific aesthetics

COMPLETE SYSTEM THINKING:
- Plan holistic user experiences, not just individual features
- Consider data relationships and connections
- Include sample/placeholder data for realism
- Design for complete user journey
```

**Enhanced JSON Response Structure**:
```json
{
  "analysis": "Deep analysis of user needs and sophisticated solution approach",
  "approach": "Professional, design-first approach using vanilla web technologies",
  "design_language": {
    "color_palette": {"primary": "#hex", "secondary": "#hex", "accent": "#hex"},
    "typography": "Font hierarchy and styling approach",
    "aesthetic": "Overall visual theme (e.g., 'Clean gallery aesthetic')"
  },
  "steps": [
    {
      "description": "Step with design and UX considerations",
      "files_affected": ["file1.js"],
      "design_notes": "Visual/UX considerations"
    }
  ],
  "system_architecture": ["How components work together cohesively"],
  "user_experience_flow": ["Key user journeys through the app"],
  "professional_touches": ["Elements that create wow factor"]
}
```

### 2. Execution Prompt (`build_execution_prompt`)

**Location**: `app/services/ai/open_router_client.rb:265`

**Key Enhancements**:
```ruby
APPROVED EXTERNAL RESOURCES:
- ✅ Tailwind CSS: Include via CDN link in HTML head section
- ✅ Shadcn/ui Components: Copy HTML/CSS directly from ui.shadcn.com
- ✅ Web fonts (Google Fonts, etc.) via CDN links
- ✅ Small utility libraries via CDN (like Alpine.js for interactivity)

SHADCN/UI COMPONENTS USAGE:
- Copy component HTML/CSS directly from https://ui.shadcn.com/
- Components work perfectly with Tailwind CDN version
- Include any required JavaScript for interactive components
- Adapt colors to match chosen design palette
- Examples: Button, Card, Dialog, Input, Select, Table, etc.
```

### 3. Fix Prompt (`build_fix_prompt`)

**Location**: `app/services/ai/open_router_client.rb:296`

**Key Enhancements**:
```ruby
APPROVED STYLING OPTIONS:
- ✅ Standard CSS3 with all modern features
- ✅ Tailwind CSS via CDN (all utility classes available)
- ✅ Combination of custom CSS + Tailwind utilities
```

## Approved Technology Stack

### Core Technologies (File-Based, No Build Process)
- **HTML5**: Valid HTML that works in iframe sandbox
- **Vanilla JavaScript**: ES6+ features, modern APIs
- **CSS3**: Standard CSS with modern features

### Professional Enhancement Libraries
- **Tailwind CSS**: `https://cdn.tailwindcss.com` (full build, all utilities)
- **Shadcn/ui Components**: Copy-paste from `https://ui.shadcn.com/`
- **Google Fonts**: Professional typography via CDN
- **Small Utilities**: Alpine.js, animation libraries via CDN

### Example Professional App Structure
```html
<!DOCTYPE html>
<html>
<head>
  <title>Professional App</title>
  <link href="https://cdn.tailwindcss.com" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
</head>
<body class="font-inter bg-slate-50">
  <!-- Shadcn/ui Button -->
  <button class="inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none disabled:pointer-events-none disabled:opacity-50 bg-slate-900 text-slate-50 hover:bg-slate-800 h-10 px-4 py-2">
    Professional Button
  </button>
  
  <!-- Shadcn/ui Card -->
  <div class="rounded-lg border bg-white text-slate-950 shadow-sm p-6 mt-4">
    <h3 class="text-xl font-semibold">Professional Title</h3>
    <p class="text-slate-600 mt-2">Professional content</p>
  </div>
  
  <script src="app.js"></script>
</body>
</html>
```

## Design Standards

### Color Palette Guidelines
- **Primary**: Deep, sophisticated colors (#1a1a1a, #0f172a)
- **Secondary**: Complementary neutrals (#64748b, #94a3b8)
- **Accent**: Purposeful highlights (#3b82f6, #d4af37)
- **Background**: Clean, professional (#ffffff, #f8fafc)

### Typography Hierarchy
- **Headings**: Clear size progression (text-3xl, text-2xl, text-xl)
- **Body**: Readable sizes (text-base, text-sm)
- **Weight**: Strategic use (font-normal, font-medium, font-semibold)
- **Fonts**: Professional web fonts (Inter, Poppins, etc.)

### Component Standards
- **Cards**: Rounded corners, subtle shadows, proper padding
- **Buttons**: Clear states (hover, focus, disabled)
- **Forms**: Accessible, well-labeled, validated
- **Layout**: Consistent spacing, proper alignment
- **Interactive**: Smooth transitions, clear feedback

## Industry-Specific Aesthetics

### Creative/Art Apps
- Gallery-inspired layouts with generous white space
- Sophisticated color palettes (charcoal, warm gold, soft grays)
- Focus on visual hierarchy and content presentation
- Card-based layouts mimicking art gallery presentations

### Business/Productivity Apps
- Dashboard-style layouts with clear data visualization
- Professional color schemes (blues, grays, whites)
- Emphasis on functionality and information density
- Grid-based layouts with consistent spacing

### E-commerce Apps
- Product-focused layouts with high-quality imagery
- Trust-building elements (reviews, testimonials, security)
- Clear call-to-action buttons and conversion paths
- Mobile-first, responsive design patterns

## Quality Assurance Checklist

### Design Quality
- [ ] Sophisticated color palette with specific hex codes
- [ ] Typography hierarchy clearly defined
- [ ] Generous white space and clean layouts
- [ ] Professional Shadcn/ui components used appropriately
- [ ] Industry-appropriate aesthetic chosen

### System Architecture
- [ ] Complete user experience flow planned
- [ ] Data relationships considered
- [ ] Component interactions designed
- [ ] Sample data included for realism

### Technical Implementation
- [ ] Valid HTML5 structure
- [ ] Tailwind CSS via CDN included
- [ ] Shadcn/ui components properly implemented
- [ ] JavaScript uses modern ES6+ features
- [ ] Error handling and validation included

### Professional Polish
- [ ] Consistent design system throughout
- [ ] Smooth interactions and transitions
- [ ] Accessible components (keyboard navigation, screen readers)
- [ ] Mobile-responsive design
- [ ] Loading states and error handling

## Testing and Validation

### Manual Testing
Run enhanced prompts with sophisticated requests:
```bash
bin/rails runner 'client = Ai::OpenRouterClient.new; response = client.analyze_app_update_request(request: "Create a professional CRM for artists", current_files: [{path: "index.html", type: "html"}], app_context: {name: "ArtistCRM", type: "business", framework: "vanilla"}); puts response[:plan][:design_language] if response[:success]'
```

### Quality Indicators
- **Color palettes** with specific hex codes mentioned
- **Shadcn/ui components** referenced appropriately  
- **Professional terminology** used in descriptions
- **Complete system thinking** evident in steps
- **Industry-specific considerations** included

## Maintenance and Updates

### Regular Review Schedule
- **Weekly**: Monitor AI output quality for regression
- **Monthly**: Review and update design standards based on trends
- **Quarterly**: Evaluate new component libraries and tools

### Key Files to Monitor
- `app/services/ai/open_router_client.rb` - Core prompt definitions
- `docs/ai-app-development-constraints.md` - Platform constraints
- `docs/ai-orchestration-design-standards.md` - This document

### Update Process
1. Test changes with sample requests
2. Update documentation simultaneously  
3. Run quality assurance checklist
4. Deploy and monitor output quality

## Success Metrics

### Base44 Quality Comparison
✅ **Design Language**: Sophisticated color palettes and typography  
✅ **Component Quality**: Professional, accessible UI components  
✅ **System Thinking**: Complete application architecture  
✅ **User Experience**: Industry-specific, user-centered design  
✅ **Visual Polish**: Modern, clean, professional appearance  
✅ **Technical Execution**: Works within OverSkill's constraints  

### Expected Outcomes
- Apps that genuinely impress users on first interaction
- Professional-grade interfaces rivaling paid SaaS tools
- Complete, functional systems rather than basic prototypes
- Industry-appropriate design languages and user experiences

---

**Critical Note**: This document represents the current state of our AI orchestration quality standards. Any changes to the prompt structure in `open_router_client.rb` should be immediately reflected here to maintain consistency and prevent quality regression.