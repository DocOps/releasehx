# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReleaseHx::Transforms::AdfToMarkdown do
  describe '.adf?' do
    it 'returns true for valid ADF document' do
      adf = {
        'type' => 'doc',
        'version' => 1,
        'content' => []
      }
      expect(described_class.adf?(adf)).to be true
    end

    it 'returns false for non-Hash object' do
      expect(described_class.adf?('string')).to be false
      expect(described_class.adf?([])).to be false
      expect(described_class.adf?(nil)).to be false
    end

    it 'returns false for Hash without doc type' do
      adf = {
        'type' => 'paragraph',
        'version' => 1,
        'content' => []
      }
      expect(described_class.adf?(adf)).to be false
    end

    it 'returns false for wrong version' do
      adf = {
        'type' => 'doc',
        'version' => 2,
        'content' => []
      }
      expect(described_class.adf?(adf)).to be false
    end

    it 'returns false for missing content' do
      adf = {
        'type' => 'doc',
        'version' => 1
      }
      expect(described_class.adf?(adf)).to be false
    end
  end

  describe '.extract_section' do
    it 'extracts section after specified heading' do
      adf = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'Introduction paragraph' }]
          },
          {
            'type' => 'heading',
            'attrs' => { 'level' => 2 },
            'content' => [{ 'type' => 'text', 'text' => 'Release Note' }]
          },
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'This is the release note content.' }]
          },
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'More note content.' }]
          }
        ]
      }

      result = described_class.extract_section(adf, heading: 'Release Note')
      expect(result['type']).to eq('doc')
      expect(result['content'].length).to eq(2)
      expect(result['content'][0]['type']).to eq('paragraph')
    end

    it 'stops at next same-level heading' do
      adf = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'heading',
            'attrs' => { 'level' => 2 },
            'content' => [{ 'type' => 'text', 'text' => 'Release Note' }]
          },
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'Release content' }]
          },
          {
            'type' => 'heading',
            'attrs' => { 'level' => 2 },
            'content' => [{ 'type' => 'text', 'text' => 'Next Section' }]
          },
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'Should not be included' }]
          }
        ]
      }

      result = described_class.extract_section(adf, heading: 'Release Note')
      expect(result['content'].length).to eq(1)
      expect(result['content'][0]['content'][0]['text']).to eq('Release content')
    end

    it 'is case-insensitive for heading match' do
      adf = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'heading',
            'attrs' => { 'level' => 2 },
            'content' => [{ 'type' => 'text', 'text' => 'release note' }]
          },
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'Content' }]
          }
        ]
      }

      result = described_class.extract_section(adf, heading: 'Release Note')
      expect(result['content'].length).to eq(1)
    end

    it 'returns empty content if heading not found' do
      adf = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'paragraph',
            'content' => [{ 'type' => 'text', 'text' => 'No heading here' }]
          }
        ]
      }

      result = described_class.extract_section(adf, heading: 'Release Note')
      expect(result['content']).to eq([])
    end
  end

  describe '.convert' do
    context 'with paragraphs' do
      it 'converts simple paragraph' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [{ 'type' => 'text', 'text' => 'Simple paragraph text.' }]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to eq('Simple paragraph text.')
      end

      it 'converts multiple paragraphs with spacing' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [{ 'type' => 'text', 'text' => 'First paragraph.' }]
            },
            {
              'type' => 'paragraph',
              'content' => [{ 'type' => 'text', 'text' => 'Second paragraph.' }]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include("First paragraph.\n\nSecond paragraph.")
      end
    end

    context 'with text marks' do
      it 'converts bold text' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                {
                  'type' => 'text',
                  'text' => 'bold text',
                  'marks' => [{ 'type' => 'strong' }]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('**bold text**')
      end

      it 'converts italic text' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                {
                  'type' => 'text',
                  'text' => 'italic text',
                  'marks' => [{ 'type' => 'em' }]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('_italic text_')
      end

      it 'converts code text' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                {
                  'type' => 'text',
                  'text' => 'code snippet',
                  'marks' => [{ 'type' => 'code' }]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('`code snippet`')
      end

      it 'converts links' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                {
                  'type' => 'text',
                  'text' => 'link text',
                  'marks' => [{ 'type' => 'link', 'attrs' => { 'href' => 'https://example.com' } }]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('[link text](https://example.com)')
      end

      it 'converts strikethrough text' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                {
                  'type' => 'text',
                  'text' => 'strikethrough',
                  'marks' => [{ 'type' => 'strike' }]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('~~strikethrough~~')
      end
    end

    context 'with lists' do
      it 'converts bullet list' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'bulletList',
              'content' => [
                {
                  'type' => 'listItem',
                  'content' => [
                    { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'First item' }] }
                  ]
                },
                {
                  'type' => 'listItem',
                  'content' => [
                    { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Second item' }] }
                  ]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('- First item')
        expect(result).to include('- Second item')
      end

      it 'converts nested bullet lists' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'bulletList',
              'content' => [
                {
                  'type' => 'listItem',
                  'content' => [
                    { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Parent item' }] },
                    {
                      'type' => 'bulletList',
                      'content' => [
                        {
                          'type' => 'listItem',
                          'content' => [
                            { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Child item' }] }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('- Parent item')
        expect(result).to include('  - Child item')
      end
    end

    context 'with code blocks' do
      it 'converts code block without language' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'codeBlock',
              'content' => [{ 'type' => 'text', 'text' => 'console.log("hello");' }]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('```')
        expect(result).to include('console.log("hello");')
      end

      it 'converts code block with language' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'codeBlock',
              'attrs' => { 'language' => 'javascript' },
              'content' => [{ 'type' => 'text', 'text' => 'const x = 42;' }]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('```javascript')
        expect(result).to include('const x = 42;')
      end
    end

    context 'with blockquotes' do
      it 'converts blockquote' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'blockquote',
              'content' => [
                { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Quoted text' }] }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('> Quoted text')
      end
    end

    context 'with panels (admonitions)' do
      it 'converts info panel to NOTE' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'panel',
              'attrs' => { 'panelType' => 'info' },
              'content' => [
                { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Info message' }] }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('> **NOTE:** Info message')
      end

      it 'converts warning panel to WARNING' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'panel',
              'attrs' => { 'panelType' => 'warning' },
              'content' => [
                { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Warning message' }] }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('> **WARNING:** Warning message')
      end

      it 'converts success panel to TIP' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'panel',
              'attrs' => { 'panelType' => 'success' },
              'content' => [
                { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Success message' }] }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('> **TIP:** Success message')
      end
    end

    context 'with tables' do
      it 'converts table with headers' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'table',
              'content' => [
                {
                  'type' => 'tableRow',
                  'content' => [
                    { 'type' => 'tableHeader',
'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Column 1' }] }] },
                    { 'type' => 'tableHeader',
'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Column 2' }] }] }
                  ]
                },
                {
                  'type' => 'tableRow',
                  'content' => [
                    { 'type' => 'tableCell',
'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Data 1' }] }] },
                    { 'type' => 'tableCell',
'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Data 2' }] }] }
                  ]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('Column 1')
        expect(result).to include('Column 2')
        expect(result).to include('---')
        expect(result).to include('Data 1')
      end
    end

    context 'with hard breaks' do
      it 'converts hard breaks to Markdown line breaks' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                { 'type' => 'text', 'text' => 'Line 1' },
                { 'type' => 'hardBreak' },
                { 'type' => 'text', 'text' => 'Line 2' }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include("Line 1  \nLine 2")
      end
    end

    context 'with excluded nodes' do
      it 'excludes specified node types' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'heading',
              'attrs' => { 'level' => 1 },
              'content' => [{ 'type' => 'text', 'text' => 'Title' }]
            },
            {
              'type' => 'paragraph',
              'content' => [{ 'type' => 'text', 'text' => 'Content' }]
            }
          ]
        }

        result = described_class.convert(adf, exclude_nodes: ['heading'])
        expect(result).not_to include('Title')
        expect(result).to include('Content')
      end
    end

    context 'with task lists' do
      it 'converts task lists with checkboxes' do
        adf = {
          'type' => 'doc',
          'version' => 1,
          'content' => [
            {
              'type' => 'taskList',
              'content' => [
                {
                  'type' => 'taskItem',
                  'attrs' => { 'state' => 'DONE' },
                  'content' => [{ 'type' => 'paragraph',
'content' => [{ 'type' => 'text', 'text' => 'Completed task' }] }]
                },
                {
                  'type' => 'taskItem',
                  'attrs' => { 'state' => 'TODO' },
                  'content' => [{ 'type' => 'paragraph',
'content' => [{ 'type' => 'text', 'text' => 'Pending task' }] }]
                }
              ]
            }
          ]
        }

        result = described_class.convert(adf)
        expect(result).to include('- [x] Completed task')
        expect(result).to include('- [ ] Pending task')
      end
    end
  end
end
