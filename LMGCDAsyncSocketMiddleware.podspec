Pod::Spec.new do |s|
  s.name         = 'LMGCDAsyncSocketMiddleware'
  s.version      = '1.0.0'
  s.license      = 'MIT'
  s.homepage     = 'https://github.com/luckymarmot/LMGCDAsyncSocketMiddleware'
  s.authors      = { 'Micha Mazaheri' => 'micha@luckymarmot.com' }
  s.summary      = A middleware for CocoaAsyncSocket's TCP GCDAsyncSocket'
  s.source       = { :git => 'https://github.com/luckymarmot/LMGCDAsyncSocketMiddleware', :tag => s.version }
  s.source_files = 'Source/*.{h,m}'
  s.requires_arc = true
end
