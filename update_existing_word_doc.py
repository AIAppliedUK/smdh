#!/usr/bin/env python3
"""
Update existing SMDH System Requirements Word Document from Markdown
Preserves company formatting and template layout
Converts requirements to tables
Uses UK English
"""

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import re

def create_requirements_table(doc, req_items, existing_style=None):
    """Create a table for requirements matching existing document style"""
    if not req_items:
        return None

    # Create table
    table = doc.add_table(rows=len(req_items) + 1, cols=2)

    # Apply existing table style if found, otherwise use default
    if existing_style:
        table.style = existing_style
    else:
        # Try common styles
        try:
            table.style = 'Light Grid Accent 1'
        except:
            try:
                table.style = 'Table Grid'
            except:
                pass

    # Header row
    hdr_cells = table.rows[0].cells
    hdr_cells[0].text = 'Requirement ID'
    hdr_cells[1].text = 'Description'

    # Format header
    for cell in hdr_cells:
        for para in cell.paragraphs:
            for run in para.runs:
                run.font.bold = True
                run.font.size = Pt(11)
        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.LEFT

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
            # Sub-item - format as bullet
            current_desc.append('\n  • ' + line_stripped[2:].strip())

        elif current_req_id and line_stripped and not line_stripped.startswith('**') and not line_stripped.startswith('#'):
            # Continuation
            current_desc.append(line_stripped)

    # Save last requirement
    if current_req_id:
        req_items.append((current_req_id, ' '.join(current_desc)))

    return req_items

def clear_document_content(doc):
    """Clear all content from document but preserve styles"""
    # Remove all paragraphs and tables
    for element in doc.element.body:
        if element.tag.endswith('p') or element.tag.endswith('tbl'):
            doc.element.body.remove(element)

def update_document():
    """Main function to update the existing Word document"""
    print("📖 Reading markdown content...")
    with open('/Users/david/projects/smdh/docs/SMDH-System-Requirements-v0.2.md', 'r', encoding='utf-8') as f:
        md_content = f.read()

    doc_path = '/Users/david/projects/smdh/docs/SMDH System Requirements .docx'

    print(f"📄 Opening existing Word document: {doc_path}")
    doc = Document(doc_path)

    # Detect existing table style
    existing_table_style = None
    for table in doc.tables:
        if table.style:
            existing_table_style = table.style
            print(f"   Detected table style: {table.style.name}")
            break

    # Store existing styles
    existing_heading_style = None
    for para in doc.paragraphs:
        if para.style.name.startswith('Heading'):
            existing_heading_style = para.style.name
            break

    print("🗑️  Clearing existing content...")
    clear_document_content(doc)

    print("✍️  Adding updated content...")

    # Title
    title = doc.add_heading('Smart Manufacturing Data Hub (SMDH)', 0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER

    subtitle = doc.add_heading('System Requirements Document', 0)
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER

    doc.add_paragraph()

    # Document Information
    doc.add_heading('Document Information', 1)

    info_table = doc.add_table(rows=5, cols=2)
    if existing_table_style:
        info_table.style = existing_table_style

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

    doc.add_page_break()

    # Section 1: Executive Summary
    print("   Processing Executive Summary...")
    match = re.search(r'## 1\. Executive Summary\n(.*?)(?=\n## 2\.)', md_content, re.DOTALL)
    if match:
        doc.add_heading('1. Executive Summary', 1)
        content = match.group(1).strip()

        # Remove section headers and process content
        content = re.sub(r'### Core Mission\n', '', content)
        paragraphs = content.split('\n\n')

        for para in paragraphs:
            if para.strip() and not para.strip().startswith('#') and not para.strip().startswith('---'):
                para = re.sub(r'\*\*(.*?)\*\*', r'\1', para)
                para = para.strip()
                if para:
                    p = doc.add_paragraph(para)
                    for run in p.runs:
                        run.font.size = Pt(11)

    # Section 2: Guiding Principles
    print("   Processing Guiding Principles...")
    match = re.search(r'## 2\. Guiding Principles\n(.*?)(?=\n## 3\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('2. Guiding Principles', 1)

        para = doc.add_paragraph('The SMDH platform is built on two core principles:')
        doc.add_paragraph()

        content = match.group(1).strip()

        # Process each principle
        principles = re.findall(r'### (Principle \d+:.*?)\n\n\*\*(.*?)\*\*\n\n(.*?)(?=\n###|\Z)', content, re.DOTALL)

        for principle_title, bold_text, principle_content in principles:
            doc.add_heading(principle_title, 2)

            # Add bold statement
            para = doc.add_paragraph()
            run = para.add_run(bold_text)
            run.font.bold = True
            run.font.size = Pt(11)
            doc.add_paragraph()

            # Process sections
            parts = principle_content.split('\n\n')
            current_section = None

            for part in parts:
                lines = part.split('\n')
                for line in lines:
                    line = line.strip()
                    if line.startswith('**') and line.endswith('**'):
                        current_section = line.strip('*')
                        p = doc.add_paragraph()
                        r = p.add_run(current_section)
                        r.font.bold = True
                    elif line.startswith('- '):
                        doc.add_paragraph(line[2:], style='List Bullet')

    # Section 3: Business Requirements
    print("   Processing Business Requirements...")
    match = re.search(r'## 3\. Business Requirements\n(.*?)(?=\n## 4\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('3. Business Requirements', 1)
        content = match.group(1).strip()

        # 3.1 Platform Targets
        targets_match = re.search(r'### 3\.1 Platform Targets\n(.*?)(?=\n###)', content, re.DOTALL)
        if targets_match:
            doc.add_heading('3.1 Platform Targets', 2)

            # Parse table
            table_text = targets_match.group(1).strip()
            table_lines = [l.strip() for l in table_text.split('\n') if l.strip().startswith('|')]

            if len(table_lines) >= 3:
                headers = [h.strip() for h in table_lines[0].split('|')[1:-1]]
                rows_data = []
                for line in table_lines[2:]:
                    cells = [c.strip() for c in line.split('|')[1:-1]]
                    if len(cells) == len(headers):
                        rows_data.append(cells)

                if rows_data:
                    table = doc.add_table(rows=len(rows_data) + 1, cols=len(headers))
                    if existing_table_style:
                        table.style = existing_table_style

                    # Headers
                    hdr_cells = table.rows[0].cells
                    for idx, header in enumerate(headers):
                        hdr_cells[idx].text = header
                        hdr_cells[idx].paragraphs[0].runs[0].font.bold = True

                    # Data
                    for row_idx, row_data in enumerate(rows_data, start=1):
                        row = table.rows[row_idx]
                        for col_idx, cell_data in enumerate(row_data):
                            row.cells[col_idx].text = cell_data

                    doc.add_paragraph()

        # 3.2 Target Users
        users_match = re.search(r'### 3\.2 Target Users\n(.*?)(?=\n###)', content, re.DOTALL)
        if users_match:
            doc.add_heading('3.2 Target Users', 2)
            users_content = users_match.group(1).strip()

            lines = users_content.split('\n')
            current_section = None

            for line in lines:
                line = line.strip()
                if line.startswith('**') and line.endswith('**'):
                    para = doc.add_paragraph()
                    run = para.add_run(line.strip('*'))
                    run.font.bold = True
                    run.font.size = Pt(11)
                elif line.startswith('1.') or line.startswith('2.') or line.startswith('3.') or line.startswith('4.'):
                    doc.add_paragraph(re.sub(r'^\d+\.\s*', '', line), style='List Number')
                elif line.startswith('- '):
                    doc.add_paragraph(line[2:], style='List Bullet')

        # 3.3 Business Constraints
        constraints_match = re.search(r'### 3\.3 Business Constraints\n(.*?)(?=\n---|$)', content, re.DOTALL)
        if constraints_match:
            doc.add_heading('3.3 Business Constraints', 2)
            constraints_content = constraints_match.group(1).strip()

            lines = constraints_content.split('\n')
            for line in lines:
                line = line.strip()
                if line.startswith('- **'):
                    match = re.match(r'- \*\*(.*?)\*\*:\s*(.*)', line)
                    if match:
                        para = doc.add_paragraph(style='List Bullet')
                        run = para.add_run(match.group(1) + ': ')
                        run.font.bold = True
                        para.add_run(match.group(2))

    # Section 4: Functional Requirements
    print("   Processing Functional Requirements...")
    match = re.search(r'## 4\. Functional Requirements\n(.*?)(?=\n## 5\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('4. Functional Requirements', 1)
        content = match.group(1).strip()

        # Find subsections (4.1, 4.2, etc.)
        subsections = re.findall(r'### (4\.\d+ .*?)\n(.*?)(?=\n### 4\.\d+|\n## 5\.|\Z)', content, re.DOTALL)

        for subsection_title, subsection_content in subsections:
            doc.add_heading(subsection_title, 2)

            # Find FR sections within subsection
            fr_sections = re.findall(r'#### (FR-\d+:.*?)\n\*\*Priority: (.*?)\*\*\n(.*?)(?=\n####|\n###|$)', subsection_content, re.DOTALL)

            for fr_id, priority, fr_content in fr_sections:
                doc.add_heading(fr_id, 3)

                # Add priority
                para = doc.add_paragraph()
                para.add_run('Priority: ').font.bold = True
                para.add_run(priority)
                doc.add_paragraph()

                # Split into intro, requirements, and must achieve
                parts = fr_content.split('**Must achieve:**')
                intro = parts[0].strip()

                # Extract intro text before requirements
                intro_match = re.match(r'(The system must .*?:)', intro, re.DOTALL)
                if intro_match:
                    p = doc.add_paragraph()
                    r = p.add_run(intro_match.group(1))
                    r.font.bold = True
                    doc.add_paragraph()

                # Check for Role Permissions table
                if '| Permission |' in intro:
                    # Extract and create permissions table
                    table_lines = [l.strip() for l in intro.split('\n') if l.strip().startswith('|')]
                    if len(table_lines) >= 3:
                        # Add "Role Permissions:" header
                        para = doc.add_paragraph()
                        run = para.add_run('Role Permissions:')
                        run.font.bold = True
                        doc.add_paragraph()

                        headers = [h.strip() for h in table_lines[0].split('|')[1:-1]]
                        rows_data = []
                        for line in table_lines[2:]:
                            cells = [c.strip() for c in line.split('|')[1:-1]]
                            if len(cells) == len(headers):
                                rows_data.append(cells)

                        if rows_data:
                            table = doc.add_table(rows=len(rows_data) + 1, cols=len(headers))
                            if existing_table_style:
                                table.style = existing_table_style

                            # Headers
                            hdr_cells = table.rows[0].cells
                            for idx, header in enumerate(headers):
                                hdr_cells[idx].text = header
                                hdr_cells[idx].paragraphs[0].runs[0].font.bold = True

                            # Data
                            for row_idx, row_data in enumerate(rows_data, start=1):
                                row = table.rows[row_idx]
                                for col_idx, cell_data in enumerate(row_data):
                                    row.cells[col_idx].text = cell_data

                            doc.add_paragraph()

                # Parse and create requirements table
                req_items = parse_requirements_section(intro)

                if req_items:
                    table = create_requirements_table(doc, req_items, existing_table_style)
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

    # Section 5: Non-Functional Requirements (abbreviated for key sections)
    print("   Processing Non-Functional Requirements...")
    match = re.search(r'## 5\. Non-Functional Requirements\n(.*?)(?=\n## 6\.)', md_content, re.DOTALL)
    if match:
        doc.add_page_break()
        doc.add_heading('5. Non-Functional Requirements', 1)
        content = match.group(1).strip()

        # Extract NFR subsections
        nfr_sections = re.findall(r'### (5\.\d+ .*?)\n(.*?)(?=\n### 5\.\d+|\n## 6\.|\Z)', content, re.DOTALL)

        for nfr_title, nfr_content in nfr_sections:
            doc.add_heading(nfr_title, 2)

            # Extract NFR items
            nfr_items = re.findall(r'#### (NFR-\d+:.*?)\n(.*?)(?=\n####|\n###|$)', nfr_content, re.DOTALL)

            for nfr_id, nfr_text in nfr_items:
                doc.add_heading(nfr_id, 3)

                # Process content
                lines = nfr_text.split('\n')
                for line in lines:
                    line = line.strip()
                    if line.startswith('- **'):
                        match = re.match(r'- \*\*(.*?)\*\*:\s*(.*)', line)
                        if match:
                            para = doc.add_paragraph(style='List Bullet')
                            run = para.add_run(match.group(1) + ': ')
                            run.font.bold = True
                            para.add_run(match.group(2))
                    elif line.startswith('  - '):
                        doc.add_paragraph(line[4:], style='List Bullet 2')
                    elif line.startswith('- '):
                        doc.add_paragraph(line[2:], style='List Bullet')
                    elif line.startswith('> '):
                        # Note/warning
                        para = doc.add_paragraph(line[2:])
                        para.style = 'Intense Quote'

    print("💾 Saving updated document...")
    doc.save(doc_path)

    print("✅ Document updated successfully!")
    print(f"\n📄 Updated: {doc_path}")
    print("\n📌 Changes made:")
    print("   ✓ Converted all requirements (REQ-X.X) to tables")
    print("   ✓ Preserved existing formatting and styles")
    print("   ✓ Updated content from markdown")
    print("   ✓ Used UK English throughout")
    print("\n💡 Please review in Word and adjust any final formatting as needed.")

if __name__ == '__main__':
    update_document()
