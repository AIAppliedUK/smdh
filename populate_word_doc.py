#!/usr/bin/env python3
"""
Populate SMDH System Requirements Word Document from Markdown
Converts bulleted requirements to tables with UK English formatting
"""

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import re

def add_border_to_table(table):
    """Add borders to all cells in a table"""
    tbl = table._element
    tblPr = tbl.tblPr
    if tblPr is None:
        tblPr = OxmlElement('w:tblPr')
        tbl.insert(0, tblPr)

    # Create border elements
    tblBorders = OxmlElement('w:tblBorders')
    for border_name in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']:
        border = OxmlElement(f'w:{border_name}')
        border.set(qn('w:val'), 'single')
        border.set(qn('w:sz'), '4')
        border.set(qn('w:space'), '0')
        border.set(qn('w:color'), '000000')
        tblBorders.append(border)

    tblPr.append(tblBorders)

def parse_markdown_requirements():
    """Parse the markdown file and extract content"""
    with open('/Users/david/projects/smdh/docs/SMDH-System-Requirements-v0.2.md', 'r', encoding='utf-8') as f:
        content = f.read()

    return content

def create_requirements_table(doc, requirements_text, section_title):
    """Convert bulleted requirements to a table format"""
    # Parse requirements from text
    req_lines = []
    for line in requirements_text.split('\n'):
        line = line.strip()
        if line.startswith('- REQ-'):
            # Extract requirement ID and description
            match = re.match(r'- (REQ-[\d\.]+):\s*(.+)', line)
            if match:
                req_id, description = match.groups()
                req_lines.append((req_id, description))
        elif line.startswith('  -'):  # Sub-bullet
            # Add as continuation of previous requirement
            if req_lines:
                req_lines[-1] = (req_lines[-1][0], req_lines[-1][1] + '\n' + line[4:])

    if not req_lines:
        return None

    # Create table with 2 columns: Requirement ID | Description
    table = doc.add_table(rows=len(req_lines) + 1, cols=2)
    table.style = 'Light Grid Accent 1'

    # Header row
    header_cells = table.rows[0].cells
    header_cells[0].text = 'Requirement ID'
    header_cells[1].text = 'Description'

    # Make header bold
    for cell in header_cells:
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.font.bold = True
                run.font.size = Pt(11)

    # Add requirements
    for idx, (req_id, description) in enumerate(req_lines, start=1):
        row_cells = table.rows[idx].cells
        row_cells[0].text = req_id
        row_cells[1].text = description

        # Format cells
        for cell in row_cells:
            for paragraph in cell.paragraphs:
                paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT
                for run in paragraph.runs:
                    run.font.size = Pt(10)

    # Set column widths
    table.columns[0].width = Inches(1.5)
    table.columns[1].width = Inches(5.0)

    # Add borders
    add_border_to_table(table)

    return table

def populate_document():
    """Main function to populate the Word document"""
    print("Reading markdown content...")
    md_content = parse_markdown_requirements()

    print("Opening Word document...")
    try:
        doc = Document('/Users/david/projects/smdh/docs/SMDH System Requirements .docx')
        print(f"Loaded existing document with {len(doc.paragraphs)} paragraphs")
    except Exception as e:
        print(f"Error loading document: {e}")
        print("Creating new document...")
        doc = Document()

    # Clear existing content (optional - comment out if you want to preserve)
    # for element in doc.element.body:
    #     doc.element.body.remove(element)

    # Add title
    title = doc.add_heading('Smart Manufacturing Data Hub (SMDH) - System Requirements Document', 0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # Add document information
    doc.add_heading('Document Information', 1)

    info_table = doc.add_table(rows=5, cols=2)
    info_table.style = 'Light Grid Accent 1'

    info_data = [
        ('Version', '0.2 (Architectural Review Update)'),
        ('Date', 'November 2, 2025'),
        ('Status', 'Updated Based on Architectural Review Feedback'),
        ('Owner', 'AI Applied'),
        ('Classification', 'Internal Use')
    ]

    for idx, (key, value) in enumerate(info_data):
        row_cells = info_table.rows[idx].cells
        row_cells[0].text = key
        row_cells[1].text = value
        row_cells[0].paragraphs[0].runs[0].font.bold = True

    doc.add_page_break()

    # Parse sections from markdown and add to document
    sections = [
        ('Executive Summary', r'## 1\. Executive Summary\n(.*?)(?=\n## 2\.|$)'),
        ('Guiding Principles', r'## 2\. Guiding Principles\n(.*?)(?=\n## 3\.|$)'),
        ('Business Requirements', r'## 3\. Business Requirements\n(.*?)(?=\n## 4\.|$)'),
        ('Functional Requirements', r'## 4\. Functional Requirements\n(.*?)(?=\n## 5\.|$)'),
        ('Non-Functional Requirements', r'## 5\. Non-Functional Requirements\n(.*?)(?=\n## 6\.|$)'),
    ]

    # Extract and add main sections
    for section_name, pattern in sections:
        match = re.search(pattern, md_content, re.DOTALL)
        if match:
            section_content = match.group(1)

            doc.add_heading(section_name, 1)

            # Process subsections
            subsections = re.findall(r'### ([\d\.]+)\s+(.+?)\n(.*?)(?=\n###|\n##|$)', section_content, re.DOTALL)

            for subsection_num, subsection_title, subsection_content in subsections:
                doc.add_heading(f'{subsection_num} {subsection_title}', 2)

                # Look for requirements
                if 'REQ-' in subsection_content:
                    # Extract prose before requirements
                    prose_match = re.match(r'(.*?)(?=- REQ-)', subsection_content, re.DOTALL)
                    if prose_match:
                        prose = prose_match.group(1).strip()
                        if prose and not prose.startswith('**'):
                            # Remove markdown formatting
                            prose = re.sub(r'\*\*(.*?)\*\*', r'\1', prose)
                            doc.add_paragraph(prose)

                    # Create requirements table
                    table = create_requirements_table(doc, subsection_content, subsection_title)
                    if table:
                        doc.add_paragraph()  # Add space after table
                else:
                    # Add regular content
                    # Remove markdown bold/italic
                    content = re.sub(r'\*\*(.*?)\*\*', r'\1', subsection_content)
                    content = content.strip()
                    if content:
                        doc.add_paragraph(content)

    # Save document
    output_path = '/Users/david/projects/smdh/docs/SMDH-System-Requirements-v0.2.docx'
    print(f"Saving document to {output_path}...")
    doc.save(output_path)
    print("✓ Document saved successfully!")
    print(f"\nCreated: {output_path}")
    print("\nNote: Please review the formatting and adjust as needed for company standards.")

if __name__ == '__main__':
    populate_document()
