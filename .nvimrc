command! DotfilesUpdate !./src/rebuild.sh
autocmd BufWritePost * silent! execute 'DotfilesUpdate'
