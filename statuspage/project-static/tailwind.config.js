const path = require('path');

/** @type {import('tailwindcss').Config} */

module.exports = {
    darkMode: ['class'],
    content: [
        /*
         * Main templates directory of the project (BASE_DIR/templates).
         * Adjust the following line to match your project structure.
         */
        path.join(__dirname, '../templates/**/*.html'),

        /*
         * Templates in other django apps (BASE_DIR/<any_app_name>/templates).
         * Adjust the following line to match your project structure.
         */
        path.join(__dirname, '../**/templates/**/*.html'),

        /**
         * JS: If you use Tailwind CSS in JavaScript, uncomment the following lines and make sure
         * patterns match your project structure.
         */
        /* JS 1: Ignore any JavaScript in node_modules folder. */
        // '!../../**/node_modules',
        /* JS 2: Process all JavaScript files in the project. */
        // '../../**/*.js',


        '../../**/css/dist',
        '../../**/css/**/*.css',

        /**
         * Python: If you use Tailwind CSS classes in Python, uncomment the following line
         * and make sure the pattern below matches your project structure.
         */
        '../../**/*.py',

        '../../**/*.ts',
    ],
    // Keep the core page layout available when the legacy bundler is invoked
    // outside the Django source tree.
    safelist: [
        'container', 'mx-auto', 'max-w-4xl', 'min-h-screen', 'pb-8', 'pt-6',
        'flex', 'flex-col', 'flex-row', 'grow', 'shrink-0', 'items-center',
        'items-end', 'justify-between', 'justify-center', 'space-x-2',
        'space-x-4', 'space-y-4', 'divide-y', 'rounded-md', 'p-2', 'p-4',
        'px-2', 'px-4', 'px-8', 'py-2', 'pl-8', 'text-2xl', 'text-5xl',
        'text-sm', 'text-xl', 'font-bold', 'shadow-lg', 'bg-zinc-100',
        'bg-zinc-300', 'bg-zinc-800', 'text-white', 'text-gray-400',
        'dark:bg-zinc-600', 'dark:bg-zinc-800', 'dark:text-white',
    ],
    theme: {
        extend: {},
    },
    plugins: [
        /**
         * '@tailwindcss/forms' is the forms plugin that provides a minimal styling
         * for forms. If you don't like it or have own styling for forms,
         * comment the line below to disable '@tailwindcss/forms'.
         */
        require('@tailwindcss/forms'),
        require('@tailwindcss/typography'),
        require('@tailwindcss/line-clamp'),
        require('@tailwindcss/aspect-ratio'),
    ],
}
