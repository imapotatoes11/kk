"""Generate the fictional academic PDF used by the README's native PDF viewer.

Requires reportlab, matplotlib, and pypdf. Computer Modern text and vector
LaTeX-style math give the fixture a conventional academic problem-set layout.
"""
from io import BytesIO
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
from matplotlib import mathtext
from matplotlib.font_manager import FontProperties
from pypdf import PdfReader, PdfWriter, Transformation
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas

matplotlib.rcParams.update({'mathtext.fontset': 'cm', 'pdf.fonttype': 42})
fonts = Path(matplotlib.get_data_path()) / 'fonts' / 'ttf'
pdfmetrics.registerFont(TTFont('ComputerModern', str(fonts / 'cmr10.ttf')))
pdfmetrics.registerFont(TTFont('ComputerModernBold', str(fonts / 'cmb10.ttf')))

output = Path(__file__).with_name('problem-set.pdf')
body = BytesIO()
canvas = Canvas(body, pagesize=(612, 792))
canvas.setTitle('MATH 241 - Problem Set 4')
canvas.setAuthor('kk documentation fixtures')
math_overlays = []
page_number = 0


def text(x, y, value, size=12, bold=False):
    canvas.setFont('ComputerModernBold' if bold else 'ComputerModern', size)
    canvas.drawString(x, y, value)


def centered(y, value, size=12, bold=False):
    canvas.setFont('ComputerModernBold' if bold else 'ComputerModern', size)
    canvas.drawCentredString(306, y, value)


def equation(latex, y, size=18, center=306):
    stream = BytesIO()
    mathtext.math_to_image(latex, stream, prop=FontProperties(size=size), format='pdf', color='black')
    stream.seek(0)
    formula = PdfReader(stream).pages[0]
    width, height = float(formula.mediabox.width), float(formula.mediabox.height)
    math_overlays.append((page_number, formula, center - width / 2, y - height / 2))


def header(number):
    text(54, 752, 'MATH 241', size=10)
    canvas.setFont('ComputerModern', 10)
    canvas.drawRightString(558, 752, 'Problem Set 4')
    canvas.setLineWidth(0.35)
    canvas.line(54, 741, 558, 741)
    centered(32, str(number), size=10)


header(1)
centered(692, 'Advanced Calculus', size=21, bold=True)
centered(662, 'Problem Set 4', size=17)
centered(634, 'Parameters, improper integrals, and logarithmic moments', size=12)
text(54, 588, 'Instructions.', bold=True)
text(128, 588, 'Show your work and justify all exchanges of limits and integrals.')
text(54, 544, '1. Convergence of a parameter integral. (8 points)', bold=True)
text(72, 518, 'Determine the values of the parameter for which the integral converges.')
equation(r'$\int_0^1 x^a\,dx$', 470)
text(54, 403, '2. Differentiation under the integral sign. (10 points)', bold=True)
text(72, 377, 'State sufficient conditions for differentiating with respect to a parameter.')
text(72, 358, 'Apply your result to the integral below and verify the answer directly.')
equation(r'$F(t)=\int_0^1 e^{tx}\,dx$', 310)
text(54, 242, '3. A limiting argument. (10 points)', bold=True)
text(72, 216, 'Use a suitable convergence theorem to evaluate the following limit.')
equation(r'$\lim_{m\to\infty}\int_0^1\frac{mx}{1+mx}\,dx$', 165)
canvas.showPage()
page_number = 1
header(2)
text(54, 702, '4. A parameter-dependent rational integral. (10 points)', bold=True)
text(72, 676, 'Evaluate the integral for a positive parameter, and explain why your')
text(72, 657, 'expression may be differentiated with respect to that parameter.')
equation(r'$F(a)=\int_0^1\frac{1}{1+ax}\,dx,\qquad a>0$', 615, size=16)

text(54, 552, '5. Logarithmic moments. (12 points)', size=14, bold=True)
text(72, 524, '(a) For a real parameter n greater than -1, evaluate the integral')
equation(r'$I_n=\int_0^1 x^n\ln x\,dx,\qquad n>-1$', 479, size=20)
text(72, 431, '(b) Use your expression to evaluate the following two cases:')
equation(r'$n=2$', 391, size=20, center=215)
equation(r'$n=5$', 391, size=20, center=397)
text(72, 351, '(c) Explain the sign of the integral without evaluating it.')

text(54, 290, '6. A second logarithmic moment. (10 points)', bold=True)
text(72, 264, 'Extend your argument from Problem 5 to determine a closed form for')
equation(r'$J_n=\int_0^1 x^n(\ln x)^2\,dx,\qquad n>-1.$', 220, size=17)
text(72, 175, 'State clearly which hypotheses justify each step of your argument.')
canvas.save()

body.seek(0)
reader = PdfReader(body)
for index, formula, x, y in math_overlays:
    reader.pages[index].merge_transformed_page(formula, Transformation().translate(x, y))
writer = PdfWriter()
for page in reader.pages:
    writer.add_page(page)
writer.add_metadata({'/Title': 'MATH 241 - Problem Set 4', '/Author': 'kk documentation fixtures'})
with output.open('wb') as stream:
    writer.write(stream)
print(output)
