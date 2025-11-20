#!/usr/bin/env python3
"""
Populate SMDH System Requirements Word Document from Markdown
Converts bulleted requirements to tables with UK English formatting
Preserves company formatting and structure
"""

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import re

def set_cell_border(cell, **kwargs):
    """
    Set cell borders
    """
    tc = cell._element
    tcPr = tc.get_or_add_tcPr()

    # Create borders element
    tcBorders = OxmlElement('w:tcBorders')
    for edge in ('top', 'left', 'bottom', 'right'):
        if edge in kwargs:
            edge_data = kwargs.get(edge)
            edge_el = OxmlElement(f'w:{edge}')
            edge_el.set(qn('w:val'), 'single')
            edge_el.set(qn('w:sz'), '4')
            edge_el.set(qn('w:space'), '0')
            edge_el.set(qn('w:color'), '000000')
            tcBorders.append(edge_el)

    tcPr.append(tcBorders)

def create_requirements_table(doc, req_items):
    """Create a table for requirements"""
    if not req_items:
        return None

    # Create table
    table = doc.add_table(rows=len(req_items) + 1, cols=2)
    table.style = 'Light List Accent 1'

    # Header row
    hdr_cells = table.rows[0].cells
    hdr_cells[0].text = 'Requirement ID'
    hdr_cells[1].text = 'Description'

    # Format header
    for cell in hdr_cells:
        cell.paragraphs[0].runs[0].font.bold = True
        cell.paragraphs[0].runs[0].font.size = Pt(11)
        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.LEFT
        # Set background colour (light blue)
        shading_elm = OxmlElement('w:shd')
        shading_elm.set(qn('w:fill'), 'D9E1F2')
        cell._element.get_or_add_tcPr().append(shading_elm)

    # Add data rows
    for idx, (req_id, description) in enumerate(req_items, start=1):
        row = table.rows[idx]
        row.cells[0].text = req_id
        row.cells[1].text = description

        # Format cells
        for cell in row.cells:
            for para in cell.paragraphs:
                para.alignment = WD_ALIGN_PARAGRAPH.LEFT
                for run in para.runs:
                    run.font.size = Pt(10)

    # Set column widths
    table.columns[0].width = Inches(1.8)
    table.columns[1].width = Inches(4.7)

    # Auto-fit
    table.autofit = True

    return table

def create_targets_table(doc, lines):
    """Create the Platform Targets table"""
    # Parse table from markdown
    table_lines = [l.strip() for l in lines if l.strip().startswith('|')]
    if len(table_lines) < 3:  # Need header, separator, and at least one row
        return None

    # Parse header
    headers = [h.strip() for h in table_lines[0].split('|')[1:-1]]

    # Parse rows
    rows_data = []
    for line in table_lines[2:]:  # Skip header and separator
        cells = [c.strip() for c in line.split('|')[1:-1]]
        if len(cells) == len(headers):
            rows_data.append(cells)

    if not rows_data:
        return None

    # Create table
    table = doc.add_table(rows=len(rows_data) + 1, cols=len(headers))
    table.style = 'Light List Accent 1'

    # Add headers
    hdr_cells = table.rows[0].cells
    for idx, header in enumerate(headers):
        hdr_cells[idx].text = header
        hdr_cells[idx].paragraphs[0].runs[0].font.bold = True
        hdr_cells[idx].paragraphs[0].runs[0].font.size = Pt(11)
        # Set background
        shading_elm = OxmlElement('w:shd')
        shading_elm.set(qn('w:fill'), 'D9E1F2')
        hdr_cells[idx]._element.get_or_add_tcPr().append(shading_elm)

    # Add data
    for row_idx, row_data in enumerate(rows_data, start=1):
        row = table.rows[row_idx]
        for col_idx, cell_data in enumerate(row_data):
            row.cells[col_idx].text = cell_data
            for para in row.cells[col_idx].paragraphs:
                for run in para.runs:
                    run.font.size = Pt(10)

    return table

def parse_requirements_section(text):
    """Parse requirements from a section"""
    req_items = []
    lines = text.split('\n')

    current_req_id = None
    current_desc = []

    for line in lines:
        line_stripped = line.strip()

        if line_stripped.startswith('- REQ-'):
            # Save previous requirement
            if current_req_id:
                req_items.append((current_req_id, ' '.join(current_desc)))

            # Start new requirement
            match = re.match(r'- (REQ-[\d\.]+):\s*(.+)', line_stripped)
            if match:
                current_req_id = match.group(1)
                current_desc = [match.group(2)]
            else:
                current_req_id = None
                current_desc = []

        elif line_stripped.startswith('  -') and current_req_id:
            # Sub-item
            current_desc.append('\n  • ' + line_stripped[2:].strip())

        elif current_req_id and line_stripped and not line_stripped.startswith('**'):
            # Continuation
            current_desc.append(line_stripped)

    # Save last requirement
    if current_req_id:
        req_items.append((current_req_id, ' '.join(current_desc)))

    return req_items

def add_section_content(doc, content):
    """Add content to document, handling different formats"""
    lines = content.split('\n')

    i = 0
    while i < len(lines):
        line = lines[i].strip()

        # Check for table
        if line.startswith('|'):
            # Collect table lines
            table_lines = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                table_lines.append(lines[i])
                i += 1

            # Create table
            table = create_targets_table(doc, table_lines)
            if table:
                doc.add_paragraph()  # Spacing
            continue

        # Check for lists
        if line.startswith('- ') or line.startswith('  -'):
            # Add as bullet point
            para = doc.add_paragraph(line[2:], style='List Bullet')
            for run in para.runs:
                run.font.size = Pt(10)
            i += 1
            continue

        # Check for bold sections
        if line.startswith('**') and line.endswith('**'):
            para = doc.add_paragraph()
            run = para.add_run(line.strip('*'))
            run.font.bold = True
            run.font.size = Pt(11)
            i += 1
            continue

        # Check for numbered lists
        if re.match(r'^\d+\.', line):
            para = doc.add_paragraph(re.sub(r'^\d+\.\s*', '', line), style='List Number')
            for run in para.runs:
                run.font.size = Pt(10)
            i += 1
            continue

        # Regular paragraph
        if line and not line.startswith('#'):
            # Remove markdown formatting
            line = re.sub(r'\*\*(.*?)\*\*', r'\1', line)
            line = re.sub(r'\*(.*?)\*', r'\1', line)

            para = doc.add_paragraph(line)
            for run in para.runs:
                run.font.size = Pt(10)

        i += 1

def populate_document():
    """Main function"""
    print("📖 Reading markdown content...")
    with open('/Users/david/projects/smdh/docs/SMDH-System-Requirements-v0.2.md', 'r', encoding='utf-8') as f:
        md_content = f.read()

    print("📄 Creating new Word document...")
    doc = Document()

    # Set up styles
    style = doc.styles['Normal']
    font = style.font
    font.name = 'Calibri'
    font.size = Pt(11)

    # Title
    title = doc.add_heading('Smart Manufacturing Data Hub (SMDH)', 0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    subtitle = doc.add_heading('System Requirements Document', 0)
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER

    doc.add_paragraph()

    # Document Information
    doc.add_heading('Document Information', 1)

    info_table = doc.add_table(rows=5, cols=2)
    info_table.style = 'Light List Accent 1'

    info_data = [
        ('Version', '0.2 (Architectural Review Update)'),
        ('Date', '2 November 2025'),
        ('Status', 'Updated Based on Architectural Review Feedback'),
        ('Owner', 'AI Applied'),
        ('Classification', 'Internal Use')
    ]

    for idx, (key, value) in enumerate(info_data):
        row = info_table.rows[idx]
        row.cells[0].text = key
        row.cells[1].text = value
        row.cells[0].paragraphs[0].runs[0].font.bold = True

        # Set background for first column
        shading_elm = OxmlElement('w:shd')
        shading_elm.set(qn('w:fill'), 'F2F2F2')
        row.cells[0]._element.get_or_add_tcPr().append(shading_elm)

    doc.add_page_break()

    # Extract main sections
    print("📝 Processing sections...")

    # Section 1: Executive Summary
    match = re.search(r'## 1\. Executive Summary\n(.*?)(?=\n## 2\.)', md_content, re.DOTALL)
    if match:
        doc.add_heading('1. Executive Summary', 1)
        content = match.group(1).strip()

        # Extract and add content
        paragraphs = content.split('\n\n')
        for para in paragraphs:
            if para.strip() and not para.strip().startswith('#'):
                # Remove markdown
                para = re.sub(r'\*\*(.*?)\*\*', r'\1', para)
                para = para.strip()
                if para:
                    p = doc.add_paragraph(para)
                    for run in p.runs:
                        run.font.size = Pt(11)

    # Section 2: Guiding Principles
    match = re.search(r'## 2\. Guiding Principles\n(.*?)(?=\n## 3\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('2. Guiding Principles', 1)
        content = match.group(1).strip()

        # Process subsections
        subsections = re.findall(r'### (Principle \d+:.*?)\n\n\*\*(.*?)\*\*\n\n(.*?)(?=\n###|\Z)', content, re.DOTALL)

        for subsection_title, bold_text, subsection_content in subsections:
            doc.add_heading(subsection_title, 2)

            # Add bold statement
            para = doc.add_paragraph()
            run = para.add_run(bold_text)
            run.font.bold = True
            run.font.size = Pt(11)
            doc.add_paragraph()

            # Process content
            parts = subsection_content.split('\n\n')
            for part in parts:
                if 'What this means:' in part or 'Key Requirements:' in part:
                    lines = part.split('\n')
                    for line in lines:
                        line = line.strip()
                        if line.startswith('**') and line.endswith('**'):
                            p = doc.add_paragraph()
                            r = p.add_run(line.strip('*'))
                            r.font.bold = True
                        elif line.startswith('- '):
                            doc.add_paragraph(line[2:], style='List Bullet')

    # Section 3: Business Requirements
    match = re.search(r'## 3\. Business Requirements\n(.*?)(?=\n## 4\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('3. Business Requirements', 1)
        content = match.group(1).strip()

        # Platform Targets
        targets_match = re.search(r'### 3\.1 Platform Targets\n(.*?)(?=\n###)', content, re.DOTALL)
        if targets_match:
            doc.add_heading('3.1 Platform Targets', 2)
            targets_content = targets_match.group(1).strip()
            table = create_targets_table(doc, targets_content.split('\n'))
            if table:
                doc.add_paragraph()

        # Target Users
        users_match = re.search(r'### 3\.2 Target Users\n(.*?)(?=\n###)', content, re.DOTALL)
        if users_match:
            doc.add_heading('3.2 Target Users', 2)
            users_content = users_match.group(1).strip()

            lines = users_content.split('\n')
            for line in lines:
                line = line.strip()
                if line.startswith('**') and line.endswith('**'):
                    p = doc.add_paragraph()
                    r = p.add_run(line.strip('*'))
                    r.font.bold = True
                    r.font.size = Pt(11)
                elif line.startswith('1.') or line.startswith('2.') or line.startswith('3.') or line.startswith('4.'):
                    doc.add_paragraph(re.sub(r'^\d+\.\s*', '', line), style='List Number')
                elif line.startswith('- '):
                    doc.add_paragraph(line[2:], style='List Bullet')

        # Business Constraints
        constraints_match = re.search(r'### 3\.3 Business Constraints\n(.*?)(?=\n---|$)', content, re.DOTALL)
        if constraints_match:
            doc.add_heading('3.3 Business Constraints', 2)
            constraints_content = constraints_match.group(1).strip()

            lines = constraints_content.split('\n')
            for line in lines:
                line = line.strip()
                if line.startswith('- **'):
                    # Parse bullet with bold start
                    match = re.match(r'- \*\*(.*?)\*\*:\s*(.*)', line)
                    if match:
                        para = doc.add_paragraph(style='List Bullet')
                        run = para.add_run(match.group(1) + ': ')
                        run.font.bold = True
                        para.add_run(match.group(2))

    # Section 4: Functional Requirements
    print("⚙️ Processing Functional Requirements...")
    match = re.search(r'## 4\. Functional Requirements\n(.*?)(?=\n## 5\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('4. Functional Requirements', 1)
        content = match.group(1).strip()

        # Find all FR sections
        fr_sections = re.findall(r'#### (FR-\d+:.*?)\n\*\*Priority: (.*?)\*\*\n(.*?)(?=\n####|\n###|$)', content, re.DOTALL)

        for fr_id, priority, fr_content in fr_sections:
            doc.add_heading(fr_id, 3)

            # Add priority
            para = doc.add_paragraph()
            para.add_run('Priority: ').font.bold = True
            para.add_run(priority)
            doc.add_paragraph()

            # Split content into intro, requirements, and acceptance criteria
            parts = fr_content.split('**Must achieve:**')

            # Intro part
            intro = parts[0].strip()

            # Extract intro text (before REQ-)
            intro_match = re.match(r'(.*?)(?=- REQ-|$)', intro, re.DOTALL)
            if intro_match:
                intro_text = intro_match.group(1).strip()
                intro_text = re.sub(r'\*\*(.*?)\*\*', r'\1', intro_text)
                if intro_text and not intro_text.startswith('The system'):
                    lines = intro_text.split('\n')
                    for line in lines:
                        line = line.strip()
                        if line:
                            doc.add_paragraph(line)

                # Check for specific intro patterns
                if 'The system must' in intro:
                    match = re.search(r'The system must.*?:', intro)
                    if match:
                        p = doc.add_paragraph()
                        p.add_run(match.group(0)).font.bold = True

            # Parse requirements
            req_items = parse_requirements_section(intro)

            if req_items:
                doc.add_paragraph()
                table = create_requirements_table(doc, req_items)
                if table:
                    doc.add_paragraph()

            # Add "Must achieve" section
            if len(parts) > 1:
                must_achieve = parts[1].strip()
                para = doc.add_paragraph()
                run = para.add_run('Must achieve:')
                run.font.bold = True
                run.font.size = Pt(11)

                lines = must_achieve.split('\n')
                for line in lines:
                    line = line.strip()
                    if line.startswith('- '):
                        doc.add_paragraph(line[2:], style='List Bullet')

    print("✅ Saving document...")
    output_path = '/Users/david/projects/smdh/docs/SMDH-System-Requirements-v0.2.docx'
    doc.save(output_path)

    print(f"✅ Document created successfully!")
    print(f"\n📄 Output: {output_path}")
    print("\n📌 Next steps:")
    print("   1. Open the document in Word")
    print("   2. Review formatting and adjust to match company standards")
    print("   3. Check tables are properly formatted")
    print("   4. Verify all UK English spelling")

if __name__ == '__main__':
    populate_document()
